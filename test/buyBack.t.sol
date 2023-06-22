// spdx-license-identifier: unlicensed
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "./utils/utils.sol";
import "../src/BuyBack.sol";
import "../src/Resolver.sol";
import "../src/mocks/MockERC4626.sol";
import "forge-std/console2.sol";

interface I3POOL {
    function add_liquidity(
        uint256[3] memory amounts,
        uint256 min_mint_amount
    ) external;
}

interface IHodler {
    function totalBonus() external view returns (uint256);
}

interface IVest {
    function totalBalance(address user) external view returns (uint256);
}

interface IGelato {
    function totalUserTokenBalance(
        address _user,
        address _token
    ) external view returns (uint256);
}

contract buyBackTest is Test {
    using stdStorage for StdStorage;

    address public constant THREE_POOL =
        address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    ERC20 public constant THREE_POOL_TOKEN =
        ERC20(address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490));
    ERC20 public constant DAI =
        ERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    ERC20 public constant USDC =
        ERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    ERC20 public constant USDT =
        ERC20(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
    ERC20 public constant GRO =
        ERC20(address(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7));
    address constant COFFEE_ADDRESS =
        address(0xc0ffEE4a95F15ff9973A17E563a8A8701D719890);
    address constant BASED_ADDRESS =
        address(0xBA5EDF9dAd66D9D81341eEf8131160c439dbA91B);
    address constant GRO_TREASURY = 0x359F4fe841f246a095a82cb26F5819E10a91fe0d;
    address constant GRO_HODLER = 0x7C268Bf50e64258835029c30C91DaA65a9E55b5a;
    address constant GRO_VESTER = 0x748218256AfE0A19a88EBEB2E0C5Ce86d2178360;
    address constant GELATO_WALLET = 0x2807B4aE232b624023f87d0e237A3B1bf200Fd99;
    address constant GELATO_KEEPER = 0x701137e5b01c7543828DF340d05b9f9BEd277F7d;
    address constant GELATO_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant ZERO = address(0x0000000000000000000000000000000000000000);
    uint256 constant MAX_UINT = type(uint256).max;

    MockERC4624 public gVault;
    BuyBack public bb;
    BuyBackResolver public resolver;

    Utils internal utils;

    address payable[] internal users;
    address internal alice;

    function setUp() public {
        utils = new Utils();
        users = utils.createUsers(1);

        alice = users[0];
        vm.label(alice, "Alice");

        vm.startPrank(BASED_ADDRESS);

        gVault = new MockERC4624(THREE_POOL_TOKEN, "test vault", "TV", 18);
        bb = new BuyBack();

        bb.setKeeper(BASED_ADDRESS);
        bb.setTokenDistribution(3000, 5000, 2000);
        bb.setToken(address(USDC), ZERO, type(uint256).max, 1, 500);
        bb.setToken(address(GRO), ZERO, 1000e18, 0, 0);
        bb.setToken(address(gVault), address(gVault), 1000e18, 2, 0);
        bb.setToken(address(THREE_POOL_TOKEN), ZERO, 1000e18, 2, 0);

        resolver = new BuyBackResolver(address(bb));
        vm.stopPrank();
    }

    function findStorage(
        address _user,
        bytes4 _selector,
        address _contract
    ) public returns (uint256) {
        uint256 slot = stdstore
            .target(_contract)
            .sig(_selector)
            .with_key(_user)
            .find();
        bytes32 data = vm.load(_contract, bytes32(slot));
        return uint256(data);
    }

    function setStorage(
        address _user,
        bytes4 _selector,
        address _contract,
        uint256 value
    ) public {
        uint256 slot = stdstore
            .target(_contract)
            .sig(_selector)
            .with_key(_user)
            .find();
        vm.store(_contract, bytes32(slot), bytes32(value));
    }

    function delta(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function genThreeCrv(
        uint256 amount,
        address _user
    ) public returns (uint256) {
        vm.startPrank(_user);
        DAI.approve(THREE_POOL, amount);
        USDC.approve(THREE_POOL, amount);
        uint256 dai = amount;
        uint256 usdc = amount / 10 ** 12;
        setStorage(
            _user,
            DAI.balanceOf.selector,
            address(DAI),
            type(uint256).max
        );
        setStorage(
            _user,
            USDC.balanceOf.selector,
            address(USDC),
            type(uint256).max
        );

        I3POOL(THREE_POOL).add_liquidity([dai, usdc, 0], 0);

        vm.stopPrank();

        return THREE_POOL_TOKEN.balanceOf(_user);
    }

    function genStable(address token, address _user) public {
        setStorage(
            _user,
            ERC20(token).balanceOf.selector,
            token,
            type(uint256).max
        );
    }

    function depositIntoVault(
        address _user,
        uint256 _amount
    ) public returns (uint256 shares) {
        uint256 balance = genThreeCrv(_amount, _user);
        vm.startPrank(_user);
        THREE_POOL_TOKEN.approve(address(gVault), balance);
        shares = gVault.deposit(_user, balance);
        vm.stopPrank();
    }

    ////////////////////////////////
    //        Utility Tests       //
    ////////////////////////////////

    function testCanSetTokens() public {
        vm.startPrank(BASED_ADDRESS);
        bb.setToken(
            address(0x514910771AF9Ca656af840dff83E8264EcF986CA),
            ZERO,
            type(uint256).max,
            1,
            500
        );
        vm.stopPrank();
        // Make sure token is set
        BuyBack.tokenData memory tokenInfo = bb.getToken(
            address(0x514910771AF9Ca656af840dff83E8264EcF986CA)
        );
        assertEq(tokenInfo.wrapped, ZERO);
        assertEq(tokenInfo.minSellAmount, type(uint256).max);
        assertEq(tokenInfo.fee, 500);
    }

    function testCannotSetTokensIfNotKeeper() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BuyBackErrors.NotOwner.selector)
        );
        bb.setToken(address(USDC), ZERO, type(uint256).max, 1, 500);
        vm.stopPrank();
    }

    function testCanRemoveTokens() public {
        vm.startPrank(BASED_ADDRESS);
        bb.setToken(
            address(0x514910771AF9Ca656af840dff83E8264EcF986CA),
            ZERO,
            type(uint256).max,
            1,
            500
        );
        bb.removeToken(address(0x514910771AF9Ca656af840dff83E8264EcF986CA));
        vm.stopPrank();
        // Make sure token is removed
        BuyBack.tokenData memory tokenInfo = bb.getToken(
            address(0x514910771AF9Ca656af840dff83E8264EcF986CA)
        );
        assertEq(tokenInfo.wrapped, ZERO);
        assertEq(tokenInfo.fee, 0);
        assertEq(tokenInfo.minSellAmount, 0);
    }

    function testCannotRemoveTokensIfNotKeeper() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BuyBackErrors.NotOwner.selector)
        );
        bb.removeToken(address(USDC));
        vm.stopPrank();
    }

    function testSetTokenDistribution() public {
        vm.startPrank(BASED_ADDRESS);
        bb.setTokenDistribution(1000, 1000, 1000);
        vm.stopPrank();
        (uint16 treasury, uint16 keeper, uint16 burner) = bb
            .tokenDistribution();
        assertEq(treasury, 1000);
        assertEq(keeper, 1000);
        assertEq(burner, 1000);
    }

    function testCannotSetTokenDistributionIfNotKeeper() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BuyBackErrors.NotOwner.selector)
        );
        bb.setTokenDistribution(1000, 1000, 1000);
        vm.stopPrank();
    }

    ////////////////////////////////
    //        Sell Tokens         //
    ////////////////////////////////
    function testSellToken() public {
        assertTrue(bb.canSellToken() == ZERO);
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();
        address tokenToSell = bb.canSellToken();
        assertTrue(tokenToSell != ZERO);

        vm.startPrank(BASED_ADDRESS);
        assertEq(USDC.balanceOf(address(bb)), 0);
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        assertGt(USDC.balanceOf(address(bb)), 0);
        assertTrue(bb.canSellToken() == ZERO);
    }

    function testSellTokenFuzz(uint256 amount) public {
        vm.assume(amount > 1000e18);
        vm.assume(amount < 1E30);
        depositIntoVault(alice, amount);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), amount);
        vm.stopPrank();
        address tokenToSell = bb.canSellToken();
        assertTrue(tokenToSell != ZERO);
        console2.log("tokenToSell", tokenToSell);
        vm.startPrank(BASED_ADDRESS);
        assertEq(USDC.balanceOf(address(bb)), 0);
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        assertGt(USDC.balanceOf(address(bb)), 0);
        assertEq(bb.canSellToken(), ZERO);
    }

    function testSendToTreasury() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();

        assertTrue(bb.canSendToTreasury() == false);

        vm.startPrank(BASED_ADDRESS);
        address tokenToSell = bb.canSellToken();
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        assertTrue(bb.canSendToTreasury() == true);
        uint256 initBuyBackBalance = USDC.balanceOf(address(bb));
        assertTrue(initBuyBackBalance > 0);

        vm.startPrank(BASED_ADDRESS);
        uint256 initTreasuryBalance = USDC.balanceOf(GRO_TREASURY);
        bb.sendToTreasury();
        assertTrue(USDC.balanceOf(address(bb)) < initBuyBackBalance);
        assertTrue(USDC.balanceOf(GRO_TREASURY) > initTreasuryBalance);

        vm.stopPrank();
    }

    function testBurnTokens() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();

        assertTrue(bb.canBurnTokens() == false);

        vm.startPrank(BASED_ADDRESS);
        address tokenToSell = bb.canSellToken();
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        assertTrue(bb.canBurnTokens() == true);

        vm.startPrank(BASED_ADDRESS);
        uint256 initBuyBackBalance = USDC.balanceOf(address(bb));
        uint256 initBonusAmount = IHodler(GRO_HODLER).totalBonus();
        assertTrue(IVest(GRO_VESTER).totalBalance(address(this)) == 0);
        bb.burnTokens();
        assertTrue(IVest(GRO_VESTER).totalBalance(address(this)) == 0);
        assertGt(IHodler(GRO_HODLER).totalBonus(), initBonusAmount);
        assertTrue(USDC.balanceOf(address(bb)) < initBuyBackBalance);

        vm.stopPrank();
    }

    function testTopUpKeeper() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();

        assertTrue(bb.canTopUpKeeper() == false);

        vm.startPrank(BASED_ADDRESS);
        address tokenToSell = bb.canSellToken();
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        // need to set neutral keeper or reduce keeper wallet to 0 prior to test
        //assertTrue(bb.canTopUpKeeper() == true);

        vm.startPrank(BASED_ADDRESS);
        uint256 initBuyBackBalance = USDC.balanceOf(address(bb));
        uint256 initGelatoBalance = IGelato(GELATO_WALLET)
            .totalUserTokenBalance(GELATO_KEEPER, GELATO_ETH);
        bb.topUpKeeper();
        assertGt(
            IGelato(GELATO_WALLET).totalUserTokenBalance(
                GELATO_KEEPER,
                GELATO_ETH
            ),
            initGelatoBalance
        );
        assertLt(USDC.balanceOf(address(bb)), initBuyBackBalance);

        vm.stopPrank();
    }

    function testRunBuyBackTrigger() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();

        assertFalse(bb.canBurnTokens());
        assertFalse(bb.canSendToTreasury());
        assertFalse(bb.canTopUpKeeper());
        assertTrue(bb.canSellToken() != address(0));
        (address token, bool treasury, bool burn, bool topUp) = bb
            .buyBackTrigger();

        assertFalse(treasury);
        assertFalse(burn);
        assertFalse(topUp);
        vm.startPrank(BASED_ADDRESS);
        address tokenToSell = bb.canSellToken();
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        (token, treasury, burn, topUp) = bb.buyBackTrigger();

        assertTrue(treasury);
        assertTrue(burn);
        assertEq(token, address(0));
        assertTrue(bb.canBurnTokens());
    }

    function testRunBuyBack() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();

        assertFalse(bb.canBurnTokens());
        // Make sure resolver triggers are aligned with bb triggers
        (bool canExec, ) = resolver.canBurnTokens();
        assertFalse(canExec);
        assertFalse(bb.canSendToTreasury());

        (canExec, ) = resolver.canSendToTreasury();
        assertFalse(canExec);

        (canExec, ) = resolver.canTopUpKeeper();
        assertFalse(canExec);
        assertFalse(bb.canTopUpKeeper());
        // Make sure we can sell tokens now
        (canExec, ) = resolver.canSellTokens();
        assertTrue(canExec);
        assertTrue(bb.canSellToken() != address(0));

        (address token, bool treasury, bool burn, bool topUp) = bb
            .buyBackTrigger();

        assertFalse(treasury);
        assertFalse(burn);
        assertFalse(topUp);
        assertTrue(token != address(0));

        vm.startPrank(BASED_ADDRESS);
        address tokenToSell = bb.canSellToken();
        bb.sellTokens(tokenToSell);
        vm.stopPrank();

        (token, treasury, burn, topUp) = bb.buyBackTrigger();

        (canExec, ) = resolver.canSendToTreasury();
        assertTrue(canExec);
        assertTrue(treasury);

        (canExec, ) = resolver.canBurnTokens();
        assertTrue(canExec);
        assertTrue(burn);

        (canExec, ) = resolver.canSellTokens();
        assertFalse(canExec);
        assertEq(token, address(0));

        assertTrue(bb.canBurnTokens());
    }

    function testSweep() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);

        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();

        uint256 balanceOfBB = ERC20(gVault).balanceOf(address(bb));
        vm.startPrank(BASED_ADDRESS);
        bb.sweep(address(gVault));
        vm.stopPrank();
        // Make sure all tokens are swept into the based address
        assertEq(ERC20(gVault).balanceOf(BASED_ADDRESS), balanceOfBB);
    }

    function testSweepNotOwner() public {
        depositIntoVault(alice, 1E26);
        vm.startPrank(alice);
        ERC20(gVault).transfer(address(bb), 1E23);
        vm.stopPrank();
        vm.expectRevert("UNAUTHORIZED");
        bb.sweep(address(gVault));
    }
}
