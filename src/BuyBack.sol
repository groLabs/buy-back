// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "./interfaces/ERC4626.sol";

library BuyBackErrors {
    error NotOwner(); // 0x30cd7471
    error NotKeeper(); // 0xf512b278
    error GelatoDepositFailed(); // 
}

interface IBurner {
    function reVest(uint256 amount) external;
}

interface IGelatoTopUp {
    function depositFunds(address _receiver, address _token, uint256 _amount) external;
    function userTokenBalance(address _user, address _token) external view returns (uint256);
}

/// Curve 3pool interface
interface ICurve3Pool {
    function get_virtual_price() external view returns (uint256);

    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;

    function balanceOf(address account) external view returns (uint256);
}

/// Curve metapool interface
interface ICurveMeta {
    function calc_withdraw_one_coin(uint256 _tokenAmount, int128 i)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[2] calldata inAmounts, bool deposit)
        external
        view
        returns (uint256);

    function add_liquidity(
        uint256[2] calldata uamounts,
        uint256 min_mint_amount
    ) external returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _tokenAmount,
        int128 i,
        uint256 min_uamount
    ) external returns (uint256);
}

/// Uniswap v2 router interface
interface IUniV2 {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// Uniswap v3 router interface
interface IUniV3 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/// Uniswap v3 pool interface
interface IUniV3_POOL {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

contract buyBack {

    uint256 constant KEEPER_MIN_ETH = 2E17;
    uint256 constant MIN_TOPUP_ETH = 5E17;
    uint256 constant MIN_SEND_TO_TREASURY = 1000E18;
    uint256 constant MIN_BURN = 1000E18;

    int128 internal constant USDC_CRV_INDEX = 1;
    uint256 internal constant DEFAULT_DECIMALS_FACTOR = 1E18;

    address constant GELATO_WALLET = 0x701137e5b01c7543828DF340d05b9f9BEd277F7d;
    address constant GELATO_KEEPER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; 
    address constant GELATO_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; 
    address constant GRO_TREASURY = 0x359F4fe841f246a095a82cb26F5819E10a91fe0d;
    address constant GRO_BURNER = 0x1F09e308bb18795f62ea7B114041E12b426b8880;
    address constant GRO_VESTOR = 0x748218256AfE0A19a88EBEB2E0C5Ce86d2178360;

    address constant THREE_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant USDC =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant GRO =
        address(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7);
    address internal constant CRV_3POOL =
        address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    ERC20 internal constant CRV_3POOL_TOKEN =
        ERC20(address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490));

    address internal constant UNI_V2 =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address internal constant UNI_V3 =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant USDC_ETH_V3 =
        address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    uint256 internal constant UNI_V3_FEE = 500;
    
    address immutable GVAULT;
    address immutable GTRANCHE;

    uint256 treasury;
    uint256 burner;
    uint256 keeper;

    struct distributionSplit {
        uint256 treasury;
        uint256 burner;
        uint256 keeper;
    }

    struct tokenData {
        address wrapped;
        uint256 minSellAmount;
    }

    address[] public tokens;
    mapping(address => tokenData) tokenInfo;
    address owner;

    mapping(address => bool) keepers;
    distributionSplit public tokenDistribution;

    event LogNewTokenAdded(address token, address wrapped, uint256 minSellAmount);
    event LogTokenRemoved(address token);
    event tokenSold(address token, uint256 amountToSell, uint256 amountToTreasury, uint256 amountToKeeper, uint256 amountToBurner);
    event TopUpKeeper(uint256 tokenAmount);
    event SendToTreasury(uint256 tokenAmount);
    event BurnTokens(uint256 tokenAmount, uint256 groAmount);
    event LogDepositReceived(address sender, uint256 value); 

    constructor(address _gVault, address _gTranche) {
        GVAULT = _gVault;
        GTRANCHE = _gTranche;
    }

    function setTokenDistribution(uint256 _treasury, uint256 _burner, uint256 _keeper) external {
        if(msg.sender != owner) revert BuyBackErrors.NotOwner();
        tokenDistribution.treasury = _treasury;
        tokenDistribution.burner = _burner;
        tokenDistribution.keeper = _keeper;
    }

    function setToken(address _token, address _wrapped, uint256 minSellAmount) external {
        if(msg.sender != owner) revert BuyBackErrors.NotOwner();
        tokens.push(_token);
        tokenData memory tokenI = tokenData(
            _wrapped,
            minSellAmount
        );
        tokenInfo[_token] = tokenI;
        emit LogNewTokenAdded(_token, _wrapped, minSellAmount);
    }

    function removeToken(address _token) external {
        if(msg.sender != owner) revert BuyBackErrors.NotOwner();

        uint256 noOfTokens = tokens.length;
        for (uint256 i = 0; i < noOfTokens - 1; i++) {
            if(tokens[i] == _token) {
                tokens[i] = tokens[noOfTokens - 1];
                tokens.pop();
                delete tokenInfo[_token];
                emit LogTokenRemoved(_token);
            }
        }
    }
    
    function canSellToken() external view returns (address token) {
        uint256 noOfTokens = tokens.length;
        for (uint256 i = 0; i < noOfTokens - 1; i++) {
            token = tokens[i];
            if(ERC20(token).balanceOf(address(this)) > tokenInfo[token].minSellAmount) {
                return token;
            }
        }
    }

    function unwrapToken(uint256 _amount, address _token, address _wrapper) internal returns (uint256, address) {
        ERC4626 wrapper = ERC4626(_wrapper);
        address asset = address(wrapper.asset());
        uint256 amount = wrapper.redeem(_amount, address(this), address(this));
        return (amount, asset);
    }

    function _sellTokens(address _token, uint256 _amount) internal returns (uint256) {
    
    }

    function sellTokens(address _token) external {
        if(msg.sender != owner || keepers[msg.sender]) revert BuyBackErrors.NotKeeper();

        uint256 amountToSell = ERC20(_token).balanceOf(address(this));
        tokenData memory tokenI = tokenInfo[_token];
        if(amountToSell < tokenI.minSellAmount) return;

        address wrapper = tokenI.wrapped;
        if (wrapper != address(0)) (amountToSell, _token) =  unwrapToken(amountToSell, _token, wrapper);
        uint256 amount = _sellTokens(_token, amountToSell);
        uint256 amountToTreasury = amount * tokenDistribution.treasury;
        uint256 amountToBurner = amount * tokenDistribution.burner;
        uint256 amountToKeeper = amount * tokenDistribution.keeper;

        treasury += amountToTreasury;
        burner += amountToBurner;
        keeper += amountToKeeper;

        emit tokenSold(_token, amountToSell, amountToTreasury, amountToKeeper, amountToBurner);
    }
    
    function canTopUpKeeper() external view returns (bool) {
        if (IGelatoTopUp(GELATO_WALLET).userTokenBalance(GELATO_KEEPER, GELATO_ETH) > KEEPER_MIN_ETH && topUpAvailable() > MIN_TOPUP_ETH) {
            return true;
        }
    }

    function topUpAvailable() public view returns (uint256) {
        uint256 balance = address(this).balance;
        balance += getPriceV3(keeper);
        return keeper;
    }

    function topUpKeeper() external returns (uint256) {
        if(msg.sender != owner || keepers[msg.sender]) revert BuyBackErrors.NotKeeper();
        uint256 _keeper = address(this).balance;
        (bool success, bytes memory result) = GELATO_WALLET.call{value: _keeper}(abi.encodeWithSignature("depositFunds(address,address,uint256)", GELATO_WALLET, GELATO_ETH, _keeper));
        if(!success) revert BuyBackErrors.GelatoDepositFailed();
        emit TopUpKeeper(_keeper);
        keeper = 0;
    }

    function sendToTreasury() external returns (uint256) {
        if(msg.sender != owner || keepers[msg.sender]) revert BuyBackErrors.NotKeeper();
        uint256 _treasury = treasury;
        ERC20(USDC).transfer(GRO_TREASURY, _treasury);
        emit SendToTreasury(_treasury);
        treasury = 0;
    }

    function burnTokens() external returns (uint256) {
        if(msg.sender != owner || keepers[msg.sender]) revert BuyBackErrors.NotKeeper();
        uint256 _burner = burner;
        uint256 amount = uniV2Swap(USDC, GRO, _burner);
        IBurner(GRO_BURNER).reVest(amount);
        emit BurnTokens(_burner, amount);
        burner = 0;
    }

    function receive() payable external {
        require(msg.data.length == 0);
        emit LogDepositReceived(msg.sender, msg.value); 
    }

    /// @notice Get price of cvx/crv in eth
    /// @param _amount Amount of rewards to swap
    function getPriceCurve(
        uint256 _amount
    ) public view returns (uint256) {
        return ICurve3Pool(THREE_POOL).calc_withdraw_one_coin(_amount, USDC_CRV_INDEX);
    }

    /// @notice Get Uniswap v2 price of token in base asset
    /// @dev rather than going through the sell path of
    ///     uni v2 => v3 => curve
    ///     we just use univ2 to estimate the value
    /// @param _token Token to swap
    /// @param _amount Amount to swap
    function getPriceV2(
        address _start,
        address _end,
        address _token,
        uint256 _amount
    ) internal view returns (uint256 price) {
        address[] memory path = new address[](2);
        path[0] = _start;
        path[1] = _end;

        uint256[] memory crvSwap = IUniV2(UNI_V2).getAmountsOut(
            _amount,
            path
        );
        return crvSwap[crvSwap.length - 1];
    }

    /// @notice Calculate the value of ETH in Base asset, taking the route:
    ///     ETH => USDC => 3Crv
    /// @param _amount Amount of token to swap
    function getPriceV3(uint256 _amount) public view returns (uint256 price) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniV3_POOL(USDC_ETH_V3).slot0();
        price = ((2 ** 192 * DEFAULT_DECIMALS_FACTOR) /
            uint256(sqrtPriceX96) ** 2);
        // we assume a dollar price of usdc and divide it by the 3pool
        //  virtual prive to get an estimate for the number of tokens we will get
        return
            _amount *
            ((price * 1E12) / ICurve3Pool(CRV_3POOL).get_virtual_price());
    }

    function uniV2Swap(address _start, address _end, uint256 _amount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _start;
        path[1] = _end;

        uint256[] memory swap = IUniV2(UNI_V2).swapExactTokensForTokens(
            _amount,
            uint256(0),
            path,
            address(this),
            block.timestamp
        );
        return swap[1];
    }

    function uniV3Swap(address _start, address _end, uint24 _fees, uint256 _amount) internal returns (uint256) {
        uint256 amounts;
        amounts = IUniV3(UNI_V3).exactInput(
            IUniV3.ExactInputParams(
                abi.encodePacked(_start, uint24(_fees), _end),
                address(this),
                block.timestamp,
                _amount,
                uint256(1)
            )
        );
    }
    function curveSwap(uint256 _amount) internal returns (uint256) {
        ICurve3Pool(THREE_POOL).remove_liquidity_one_coin(
            _amount,
            USDC_CRV_INDEX,
            0
        );

    }
}
