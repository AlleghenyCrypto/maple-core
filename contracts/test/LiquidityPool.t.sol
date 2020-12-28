pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/ILiquidityPoolFactory.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityPoolFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../LiquidityPool.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function createLiquidityPool(
        address liquidityPoolFactory, 
        address liquidityAsset,
        address stakeAsset,
        uint256 stakingFeeBasisPoints,
        uint256 delegateFeeBasisPoints,
        string memory name,
        string memory symbol
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = ILiquidityPoolFactory(liquidityPoolFactory).createLiquidityPool(
            liquidityAsset,
            stakeAsset,
            stakingFeeBasisPoints,
            delegateFeeBasisPoints,
            name,
            symbol 
        );
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }
}

contract LP {
    function try_deposit(address lPool, uint256 amt)  external returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(lPool).call(abi.encodeWithSignature(sig, amt));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }
}

contract LiquidityPoolTest is TestUtil {

    ERC20                  fundsToken;
    MapleToken             mapleToken;
    MapleGlobals           globals;
    LiquidityPoolFactory   liquidityPoolFactory;
    StakeLockerFactory     stakeLockerFactory;
    LiquidityLockerFactory liquidityLockerFactory; 
    LiquidityPool          lPool; 
    DSValue                daiOracle;
    DSValue                usdcOracle;
    PoolDelegate           ali;
    LP                     bob;
    IBPool                 bPool;

    function setUp() public {

        fundsToken             = new ERC20("FundsToken", "FT");
        mapleToken             = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals                = new MapleGlobals(address(this), address(mapleToken));
        stakeLockerFactory     = new StakeLockerFactory();
        liquidityLockerFactory = new LiquidityLockerFactory();
        liquidityPoolFactory   = new LiquidityPoolFactory(address(globals), address(stakeLockerFactory), address(liquidityLockerFactory));
        daiOracle              = new DSValue();
        usdcOracle             = new DSValue();
        ali                    = new PoolDelegate();
        bob                    = new LP();

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mapleToken.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 ether);          // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mapleToken), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(mapleToken.balanceOf(address(bPool)),   100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        globals.setPoolDelegateWhitelist(address(ali), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(ali), bPool.balanceOf(address(this)));

        lPool = LiquidityPool(ali.createLiquidityPool(
            address(liquidityPoolFactory),
            DAI,
            address(bPool),
            500,
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));

        globals.setMapleBPool(address(bPool));
        globals.setMapleBPoolAssetPair(USDC);
        globals.setStakeRequired(100 * 10 ** 6);
    }

    function test_stake_and_finalize() public {
        address stakeLocker = lPool.stakeLockerAddress();

        ali.approve(address(bPool), stakeLocker, uint(-1));
        assertEq(bPool.balanceOf(address(ali)),               100 * WAD);
        assertEq(bPool.balanceOf(stakeLocker),                0);
        assertEq(IERC20(stakeLocker).balanceOf(address(ali)), 0);

        ali.stake(lPool.stakeLockerAddress(), bPool.balanceOf(address(ali)) / 2);

        assertEq(bPool.balanceOf(address(ali)),               50 * WAD);
        assertEq(bPool.balanceOf(stakeLocker),                50 * WAD);
        assertEq(IERC20(stakeLocker).balanceOf(address(ali)), 50 * WAD);

        lPool.finalize();
    }

    function test_deposit() public {
        address stakeLocker     = lPool.stakeLockerAddress();
        address liquidityLocker = lPool.liquidityLockerAddress();

        ali.approve(address(bPool), stakeLocker, uint(-1));
        ali.stake(lPool.stakeLockerAddress(), bPool.balanceOf(address(ali)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        assertTrue(!bob.try_deposit(address(lPool), 100 ether)); // Not finalized

        lPool.finalize();

        assertTrue(!bob.try_deposit(address(lPool), 100 ether)); // Not approved

        bob.approve(DAI, address(lPool), uint(-1));

        assertEq(IERC20(DAI).balanceOf(address(bob)),    100 ether);
        assertEq(IERC20(DAI).balanceOf(liquidityLocker), 0);
        assertEq(lPool.balanceOf(address(bob)),          0);

        assertTrue(bob.try_deposit(address(lPool), 100 ether));

        assertEq(IERC20(DAI).balanceOf(address(bob)),    0);
        assertEq(IERC20(DAI).balanceOf(liquidityLocker), 100 ether);
        assertEq(lPool.balanceOf(address(bob)),          100 ether);
    }
}