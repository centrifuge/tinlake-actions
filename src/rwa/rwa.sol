// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

interface ERC20Like {
    function approve(address usr, uint amount) external;
    function balanceOf(address usr) external view returns (uint);
    function totalSupply() external view returns (uint);
}

interface PSMLike {
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
}

interface OperatorLike {
    function supplyOrder(uint amount) external;
    function redeemOrder(uint amount) external;
    function tranche() external view returns (address);
    function disburse() external returns(uint payoutCurrencyAmount, uint payoutTokenAmount, uint remainingSupplyCurrency,  uint remainingRedeemToken);
}

interface TrancheLike {
    function users(address) external view returns (uint, uint, uint);
}

interface CoordinatorLike {

}

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode ) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
}

contract RWAOperatorActions {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth { require(wards[msg.sender] == 1); _; }

    address immutable public psmJoin;
    PSMLike immutable public psm;
    ERC20Like immutable public usdc;
    ERC20Like immutable public dai;
    
    LendingPoolLike immutable public lendingPool;
    address immutable public aToken;

    struct TinlakePool {
        OperatorLike operator;
        TrancheLike tranche;
        CoordinatorLike coordinator;
    }

    mapping (address => TinlakePool) public pools;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(address indexed token, address indexed operator, address indexed tranche, address coordinator);

    constructor(address psmJoin_, address psm_, address usdc_, address dai_, address lendingPool_, address aToken_) {
        psmJoin = psmJoin_;
        psm = PSMLike(psm_);
        usdc = ERC20Like(usdc_);
        dai = ERC20Like(dai_);
        lendingPool = LendingPoolLike(lendingPool_);
        aToken = aToken_;
    }

    // --- Administration ---
    function file(address token, address operator, address tranche, address coordinator) public auth {
        pools[token] = TinlakePool(OperatorLike(operator), TrancheLike(tranche), CoordinatorLike(coordinator));
        emit File(token, operator, tranche, coordinator);
    }

    // --- Swapping ---
    function swapDAItoUSDC(uint amount) public {
        usdc.approve(psmJoin, amount);
        psm.sellGem(address(this), amount);
    }

    function swapUSDCtoDAI(uint amount) public {
        dai.approve(address(psm), amount);
        psm.buyGem(address(this), amount);
    }

    // --- Pool Interactions ---
    function investInDrop(address token, uint amount) public {
        require(address(pools[token].operator) != address(0), "invalid-token");
        TinlakePool memory pool = pools[token];
        (, uint supplyCurrencyAmount,) = pool.tranche.users(msg.sender);
        pool.operator.supplyOrder(supplyCurrencyAmount + amount);
    }

    function disburseDepositBorrow(address token) public {
        require(address(pools[token].operator) != address(0), "invalid-token");
        TinlakePool memory pool = pools[token];
        (, uint payoutTokenAmount,,) = pool.operator.disburse();
        
        ERC20Like(token).approve(address(lendingPool), payoutTokenAmount);
        lendingPool.deposit(token, payoutTokenAmount, msg.sender, 0);

        // TODO: borrow (with amount + overcollateralization)
    }

    function repayWithdrawRedeem(address token, uint amount) public {
        require(address(pools[token].operator) != address(0), "invalid-token");
        TinlakePool memory pool = pools[token];


        // TODO: repay
        // TODO: withdraw
        // TODO: redeem
    }

    function disburseMultiple(address[] memory tokens) public {
        // loop over tokens
        // calcDisburse to check
        // disburseDepositBorrow if payoutTokenAmount > 0, else disburse if payoutCurrencyAmount > 0
    }

    // --- 1-step  ---
    // function flashloan(address token, uint amount) public {
        
    // }

    // --- View methods ---
    function currentExposure(address token) public view returns (uint) {
        return ERC20Like(token).balanceOf(aToken);
    }

    // function currentParticipation(address token) public view returns (uint) {
    //     return rdiv(currentExposure(token), ERC20Like(token).totalSupply());
    // }

}
