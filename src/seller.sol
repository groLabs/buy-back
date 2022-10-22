// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

/// Curve 3pool interface
interface IThreePool {
    function add_liquidity(uint256[3] memory amounts, uint256 minMintAmount)
        external;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;

    function get_virtual_price() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

/// CRV-ETH and CVX-ETH pool interface
interface ICurveRewards {
    function exchange(
        uint256 from,
        uint256 to,
        uint256 _from_amount,
        uint256 _min_to_amount,
        bool use_eth
    ) external returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
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

contract seller {

    address internal constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address internal constant USDC =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address internal constant CRV_3POOL =
        address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    IERC20 internal constant CRV_3POOL_TOKEN =
        IERC20(address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490));

    address internal constant UNI_V2 =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address internal constant UNI_V3 =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant USDC_ETH_V3 =
        address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    uint256 internal constant UNI_V3_FEE = 500;

    enum AMM{ UNIv2, UNIv3, ConvexStable }
    AMM sellPath;
    AMM constant defaultChoice = FreshJuiceSize.UNIv2;

    struct token {
        address[] path;
        AMM amm;
    }

    mapping (address => token) tokenData;

    function sellTokens() external {

    }

    function uniV3Swap(address _start, address _end, uint24 fees) {
        uint256 amounts;
        amounts = IUniV3(UNI_V3).exactInput(
            IUniV3.ExactInputParams(
                abi.encodePacked(address(WETH), uint24(UNI_V3_FEE), USDC),
                address(this),
                block.timestamp,
                wethAmount,
                uint256(1)
            )
        );
    }

    function uniV2Swap(address _start, address _end, uint24 fees) {
        uint256[] memory swap = IUniV2(UNI_V2).swapExactTokensForTokens(
            reward_amount,
            uint256(0),
            _getPath(rewardTokens[i], true),
            address(this),
            block.timestamp
        );
    }

    function curveSwap(address _start, address _end, uint24 fees) {
        IThreePool().remove_liquidity_one_coin(
            meta_amount,
            CRV3_INDEX,
            0
        );
    }
}
