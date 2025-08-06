1. SetRCC(IERC20 indexed RCC)
   功能：记录 RCC 代币地址的设置或更新。
   触发时机：当管理员通过setRCC函数设置或修改 RCC 代币合约地址时触发。
   作用：让外部系统知晓当前合约使用的 RCC 代币地址，确保奖励发放和查询的准确性。
2. PauseWithdraw() 和 UnpauseWithdraw()
   功能：分别记录 “提现功能” 的暂停和恢复状态。
   触发时机：
   管理员调用pauseWithdraw()暂停提现时，触发PauseWithdraw；
   管理员调用unpauseWithdraw()恢复提现时，触发UnpauseWithdraw。
   作用：通知外部系统当前提现功能的可用性，避免用户在暂停期间尝试提现操作。
3. PauseClaim() 和 UnpauseClaim()
   功能：分别记录 “领取奖励功能” 的暂停和恢复状态。
   触发时机：
   管理员调用pauseClaim()暂停领取奖励时，触发PauseClaim；
   管理员调用unpauseClaim()恢复领取奖励时，触发UnpauseClaim。
   作用：通知外部系统当前奖励领取功能的状态，帮助用户了解是否可以领取奖励。
4. SetStartBlock(uint256 indexed startBlock)
   功能：记录挖矿开始区块的设置或修改。
   触发时机：管理员通过setStartBlock函数调整挖矿开始区块时触发。
   作用：追踪挖矿周期的起始时间变更，辅助计算奖励发放的时间范围。
5. SetEndBlock(uint256 indexed endBlock)
   功能：记录挖矿结束区块的设置或修改。
   触发时机：管理员通过setEndBlock函数调整挖矿结束区块时触发。
   作用：追踪挖矿周期的结束时间变更，帮助用户判断挖矿是否已结束。
6. SetRCCPerBlock(uint256 indexed RCCPerBlock)
   功能：记录每区块 RCC 奖励数量的设置或修改。
   触发时机：管理员通过setRCCPerBlock函数调整每区块的 RCC 奖励时触发。
   作用：追踪奖励发放速率的变化，辅助用户预估收益（奖励越多，用户收益潜力越大）。
7. AddPool(address indexed stTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks)
   功能：记录新质押池的创建信息。
   触发时机：管理员通过addPool函数添加新质押池时触发。
   参数说明：
   stTokenAddress：该池接受的质押代币地址（原生币为 0x0）；
   poolWeight：池子权重（决定奖励分配比例）；
   lastRewardBlock：初始奖励结算区块；
   其他参数：最小质押量、解押锁定区块数。
   作用：通知外部系统有新质押池可用，方便用户选择质押资产。
8. UpdatePoolInfo(uint256 indexed poolId, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks)
   功能：记录质押池关键参数的更新。
   触发时机：管理员通过updatePool函数修改池子的 “最小质押量” 或 “解押锁定区块数” 时触发。
   作用：追踪池子规则的变化，帮助用户了解质押和解押的最新限制。
9. SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight)
   功能：记录质押池权重的调整。
   触发时机：管理员通过setPoolWeight函数修改池子权重时触发。
   作用：权重决定了池子分得的奖励比例，该事件帮助用户了解各池的奖励分配能力变化（权重越高，分得奖励越多）。
10. UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalRCC)
    功能：记录质押池奖励状态的更新（即奖励结算）。
    触发时机：每次调用updatePool或massUpdatePools结算池子奖励时触发（如用户质押 / 解押前，系统会先结算未分配的奖励）。
    参数说明：
    lastRewardBlock：本次结算的截止区块；
    totalRCC：本次结算该池获得的总 RCC 奖励。
    作用：追踪池子奖励的实时结算情况，辅助计算用户待领奖励。
11. Deposit(address indexed user, uint256 indexed poolId, uint256 amount)
    功能：记录用户的质押行为。
    触发时机：用户通过deposit（ERC20 质押）或depositnativeCurrency（原生币质押）函数成功质押资产时触发。
    作用：追踪用户的质押记录，包括质押的池子、数量，方便用户查询自己的质押历史。
12. RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount)
    功能：记录用户的解押请求。
    触发时机：用户通过unstake函数发起解押申请时触发（此时资产并未立即到账，而是进入锁定状态）。
    作用：追踪用户的解押申请，帮助用户了解自己的解押排队情况（需等待锁定区块数后才能提现）。
13. Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber)
    功能：记录用户的提现行为（即解押资产到账）。
    触发时机：用户通过withdraw函数提取已解锁的解押资产时触发。
    作用：追踪用户实际到账的解押资产，包括数量和提现区块，作为资产到账的凭证。
14. Claim(address indexed user, uint256 indexed poolId, uint256 RCCReward)
    功能：记录用户领取 RCC 奖励的行为。
    触发时机：用户通过claim函数成功领取 RCC 奖励时触发。
    作用：追踪用户的奖励领取记录，包括领取的数量和对应池子，方便用户核对收益。