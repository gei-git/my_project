// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// 引入OpenZeppelin的ERC20接口和安全库
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// 引入OpenZeppelin的可升级合约相关库
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract RCCStake is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // ************************************** 常量与权限 **************************************

    // 定义合约管理员角色
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // 定义合约升级员角色
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    // 原生币池的池ID（第一个池）
    uint256 public constant nativeCurrency_PID = 0;

    // ************************************** 数据结构 **************************************

    /*
    任何时刻，用户应得但尚未分发的RCC数量为：
    pending RCC = (user.stAmount * pool.accRCCPerST) - user.finishedRCC

    用户每次存入或取出质押时，流程如下：
    1. 更新池子的accRCCPerST和lastRewardBlock
    2. 发放用户待领取的RCC
    3. 更新用户的stAmount
    4. 更新用户的finishedRCC
    */

    /**
     * @dev 质押池结构体
     */
    struct Pool {
        address stTokenAddress;      // 质押代币地址（原生币为0x0）
        uint256 poolWeight;          // 池子权重（决定奖励分配比例）
        uint256 lastRewardBlock;     // 上次分配奖励的区块号
        uint256 accRCCPerST;         // 累计每个质押代币分到的RCC（扩大1e18精度）
        uint256 stTokenAmount;       // 当前池子总质押量
        uint256 minDepositAmount;    // 最小质押数量
        uint256 unstakeLockedBlocks; // 解押后需要等待的区块数
    }

    /**
     * @dev 解押请求结构体
     */
    struct UnstakeRequest {
        // 质押数量
        uint256 amount;
        // 可提现的区块号
        uint256 unlockBlocks;
    }

    /**
     * @dev 用户结构体
     */

    struct User {
        // 用户质押的代币数量
        uint256 stamount;
        // 用户已领取的RCC数量
        uint256 finshedRCC;
        // 用户未领取的RCC数量
        uint256 pendingRCC;
        // 用户的解押请求队列
        UnstakeRequest[] requests;


    }
    // 挖矿开始的区块号
    uint256 public startBlock;
    // 挖矿结束的区块号
    uint256 public endBlock;
    // 每个区块的RCC奖励数量
    uint256 public RCCPerBlock;

    // 是否暂停体现
    bool public withdrawPaused;
    // 是否暂停领取奖励
    bool public claimPaused;

    // RCC代币合约地址
    IERC20 public RCC;

    // 总权重（所有池子的权重之和）
    uint256 public totalPoolWeight;
    // 质押池列表
    Pool[] public pool;

    // 用户信息映射：池ID => 用户地址 => 用户信息
    mapping(uint256 => mapping(address => User)) public user;

    // ************************************** 事件 **************************************
    /**
        * @dev 当RCC地址被设置时触发
        * @param _RCC 新的RCC代币合约地址
        功能：记录 RCC 代币地址的设置或更新。
        触发时机：当管理员通过setRCC函数设置或修改 RCC 代币合约地址时触发。
        作用：让外部系统知晓当前合约使用的 RCC 代币地址，确保奖励发放和查询的准确性。
        */
    event SetRCC(IERC20 indexed _RCC);
    // 暂停提现功能时触发
    event pausedWithdraw();
    // 恢复提现功能时触发
    event UnpausedWithdraw();
    // 暂停领取奖励功能时触发
    event pauseClaim();
    // 恢复领取奖励功能时触发
    event UnpauseClaim();
    // 设置挖矿开始区块时触发
    event SetStartBlock(uint256 indexed _startBlock);
    // 设置挖矿结束区块时触发
    event SetEndBlock(uint256 indexed _endBlock);
    // 添加新质押池时触发
    event AddPool(
        address indexed _stTokenAddress,
        uint256 indexed _poolWeight,
        uint256 indexed _lastRewardBlock,
        uint256 _minDepositAmount,
        uint256 _unstakeLockedBlocks
    );
    // 更新质押池信息时触发
    event UpdataPoolInfo(
        uint256 indexed _pid,
        uint256 _minDepositAmount,
        uint256 _unstakeLockedBlocks
    );
    // 设置质押池权重时触发
    event SetPoolWeight(
        uint256 indexed _pid,
        uint256 indexed _poolWeight,
        bool _withUpdate
    );

    // ************************************** 修饰符 **************************************
    // 合约中的修饰符（Modifier）用于在函数执行前 / 后自动执行特定逻辑（如权限检查、参数验证、状态限制等）

    // 检查池ID是否有效
    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "invalid pid");
        _;
    }

    // 检查 “领取奖励” 功能是否未被暂停（即claimPaused为false）
    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    // 检查 “提现” 功能是否未被暂停（即withdrawPaused为false）
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    // ************************************** 初始化函数 **************************************

    /**
     * @notice 初始化合约，设置RCC地址、起止区块、每区块奖励
     */
    // initializer修饰符：来自Initializable库，确保该函数只能被调用一次
    function initialize(
        IERC20 _RCC,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _RCCPerBlock
    ) public initializer {
        // 挖矿开始区块（_startBlock）不能晚于结束区块（_endBlock），否则挖矿周期无效
        // 每区块奖励（_RCCPerBlock）必须大于 0，否则无奖励可分配，合约失去意义。
        require(_startBlock <= _endBlock && _RCCPerBlock > 0, "invalid parameters");
        // 合约继承了AccessControlUpgradeable（权限管理）、UUPSUpgradeable（可升级逻辑）、PausableUpgradeable（暂停功能）三个父合约。
        // 调用父合约的__xxx_init()函数，初始化它们的内部状态（如权限角色的基础设置、可升级标记、暂停状态变量等），确保父合约功能正常可用。

        // 初始化AccessControlUpgradeable父合约
        __AccessControl_init();
        // 初始化UUPSUpgradeable父合约
        __UUPSUpgradeable_init();
        // 初始化PausableUpgradeable父合约
        __Pausable_init();
        // 授予默认管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // 授予合约升级角色
        _grantRole(UPGRADE_ROLE, msg.sender);
        // 授予日常管理员角色
        _grantRole(ADMIN_ROLE, msg.sender);


        // 调用合约内部的setRCC函数（管理员函数），将_RCC参数设置为当前合约使用的奖励代币地址。
        // 后续用户领取的奖励、合约计算的收益，都基于该 RCC 代币。
        setRCC(_RCC);

        // 记录挖矿开始区块
        startBlock = _startBlock;
        // 记录挖矿结束区块
        endBlock = _endBlock;
        // 记录每区块的RCC奖励数量
        RCCPerBlock = _RCCPerBlock;
    }
    // UUPS升级函数
    /**
        * @dev 重写UUPSUpgradeable的授权升级函数
        * @param newImplementation 新的实现合约地址
        * @notice _authorizeUpgrade 是 UUPSUpgradeable 父合约中定义的抽象函数，
            必须在子合约中重写实现，否则合约无法编译。
        * @notice onlyRole(UPGRADER_ROLE):来自 AccessControlUpgradeable 库。
            它要求调用者（即触发升级的地址）必须拥有 UPGRADER_ROLE 角色，否则会拒绝升级操作
        * @notice override 关键字表示该函数是对父合约中 抽象函数的重写
        * @notice 函数体为空（{}），因为它的核心作用是权限检查，而非处理业务逻辑。
            权限检查由 onlyRole 修饰符完成，只要通过修饰符的验证，函数就会成功执行，允许升级继续
        */

    function _authorizeUpgrade(address newImplementation)
        internal override
        onlyRole(UPGRADER_ROLE)
    {}

    // ************************************** 管理员函数 **************************************
    /**
     * @notice 设置RCC代币地址
     * @param _RCC 新的RCC代币合约地址
     */
    function setRCC(IERC20 _RCC) public onlyRole(ADMIN_ROLE)  {
        RCC = _RCC;
        emit SetRCC(_RCC);
    }

    /**
     * @notice 暂停提现功能
     * 这段代码是 RCCStake 合约中用于暂停提现功能的管理员函数，属于合约安全机制的一部分，
       用于在紧急情况下（如发现异常交易、合约漏洞等）临时冻结用户的提现操作，保护用户资产安全
     *
     */
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused,"withdraw is paused");
        withdrawPaused = true;
        emit pausedWithdraw();
    }

    /**
     * @notice 恢复提现功能
     * 这段代码是 RCCStake 合约中用于恢复提现功能的管理员函数，属于合约安全机制的一部分，
       用于在紧急情况解除后，重新开放用户的提现操作，确保用户能够正常提取其质押的资产
     *
     */
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused,"withdraw is not paused");
        withdrawPaused = false;
        emit UnpausedWithdraw();
    }

    /**
     * @notice 暂停领取奖励功能
     * 这段代码是 RCCStake 合约中用于暂停领取奖励功能的管理员函数，属于合约安全机制的一部分，
       用于在紧急情况下（如发现异常交易、合约漏洞等）临时冻结用户的奖励领取操作，保护用户资产安全
     */
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim is paused");
        claimPaused = true;
        emit pauseClaim();
    }

    /**
     * @notice 恢复领取奖励功能
     * 这段代码是 RCCStake 合约中用于恢复领取奖励功能的管理员函数，属于合约安全机制的一部分，
       用于在紧急情况解除后，重新开放用户的奖励领取操作，确保用户能够正常提取其质押的奖励
     */
    function UnpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim is not paused");
        claimPaused = false;
        emit UnpauseClaim();

    }

    /**
     * @notice 设置挖矿开始区块
     * @param _startBlock 新的挖矿开始区块号
     * @dev 只能由管理员调用，且新的开始区块不能晚于结束区块
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "invalid start block");
        startBlock = _startBlock;
        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice 设置挖矿结束区块
     * @param _endBlock 新的挖矿结束区块号
     * @dev 只能由管理员调用，且新的结束区块不能早于开始区块
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(_endBlock >= startBlock, "invalid end block");
        endBlock = _endBlock;
        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice 设置每区块的RCC奖励数量
     * @param _RCCPerBlock 新的每区块RCC奖励数量
     * @dev 只能由管理员调用，且奖励数量必须大于0
     */
    function setRCCPerBlock(uint256 _RCCPerBlock) public onlyRole(ADMIN_ROLE) {
        require(_RCCPerBlock > 0, "RCCPerBlock must be greater than 0");
        RCCPerBlock = _RCCPerBlock;
    }

    /**
     * @notice 添加新的质押池
     * @param _stTokenAddress 质押代币地址（原生币为0x0）
     * @param _poolWeight 池子权重（决定奖励分配比例）
     * @param _minDepositAmount 最小质押数量
     * @param _unstakeLockedBlocks 解押后需要等待的区块数
     * @param _withUpdate 是否更新所有池的状态
     */
    function addPool(
        address _stTokenAddress,
        uint256 _poolWeight,
        uint256 _minDepositAmount,
        uint256 _unstakeLockedBlocks,
        bool _withUpdate
    ) public onlyRole(ADMIN_ROLE) {
        // 如果pool.length > 0就代表已经有代币池了
        if(pool.length > 0) {
            // 那么新添加的池子必须有质押代币地址，不能是原生币池
            // 在 Solidity 中，address(0x0) 是一个特殊地址，通常用来表示 “原生币”
            // address(0x0) 是 Solidity 中对 “20 字节全零地址” 的标准表示
            require(_stTokenAddress != address(0x0), "invalid staking token address");
        } else {
            // 如果是第一个池子（原生币池），质押代币地址必须是0x0
            require(_stTokenAddress == address(0x0), "invalid staking token address");
        }

        // _unstakeLockedBlocks 是新增池子的 “解押后锁定区块数”
        //（用户发起解押后，需要等待该数量的区块才能提现）
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        //要求当前区块号必须小于挖矿结束区块号,确保只能在挖矿周期内新增质押池。
        require(block.number < endBlock, "Already ended");

        if(_withUpdate) {
            // 如果需要更新所有池的状态，调用massUpdatePools();函数
            massUpdatePools();
        }

        // 新池的初始 “奖励结算基准区块”，后续奖励将从该区块开始计算
        // 若 block.number > startBlock：当前区块已超过挖矿开始区块（即挖矿已启动），则新池的初始结算区块设为 block.number
        // 若 block.number <= startBlock：当前区块未到挖矿开始时间（即挖矿尚未启动），则新池的初始结算区块设为 startBlock
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        // 将新建池子的权重加入到权重总和中
        totalPoolWeight = totalPoolWeight + _poolWeight;

        // 将新池子添加到池子列表中
        pool.push(
            Pool({
                stTokenAddress: _stTokenAddress,
                poolWeight: _poolWeight,
                lastRewardBlock: lastRewardBlock,
                accRCCPerST: 0,
                stTokenAmount: 0,
                minDepositAmount: _minDepositAmount,
                unstakeLockedBlocks: _unstakeLockedBlocks
            })
        );

        emit AddPool(_stTokenAddress, _poolWeight,lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice 更新质押池的参数
     * @param _pid 池ID
     * @param _minDepositAmount 最小质押数量
     * @param _unstakeLockedBlocks 解押后需要等待的区块数
     */
    function updataPool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        // 更新指定池子的最小质押数量和解押锁定区块数
        pool[_pid].minDepositAmount = _minDepositAmount;
        pool[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        emit UpdataPoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }


    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "invalid pool weight");
        // 如果需要更新所有池的状态，调用massUpdatePools();函数
        if(_withUpdate) {
            massUpdatePools();
        }

        // 更新总权重：先减去旧的池子权重，再加上新的池子权重
        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        pool[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, _withUpdate);

    }
}
