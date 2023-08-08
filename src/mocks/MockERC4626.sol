// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";


contract MockERC4624 is ERC20 {
    ERC20 public immutable asset;
    uint256 public totalAssets;

    mapping(address => uint256) balance;

    uint256 private _decimals;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _decimal
    ) ERC20(_name, _symbol, 18) {
        asset = _asset;
        _decimals = _decimal;
    }

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external {
        _burn(_account, _amount);
    }

    function setTotalAssets(uint256 _newTotal) external {
        totalAssets = _newTotal;
    }

    function redeem(uint256 _amount, address _account, address _receiver) external returns (uint256) {
        uint256 amnt = convertToAssets(_amount);
        _burn(_account, _amount);
        asset.transfer(_receiver, amnt);
        return(amnt);
    }

    function deposit(address _account, uint256 _amount) external returns (uint256){
        asset.transferFrom(_account, address(this), _amount);
        _mint(_account, _amount);
        totalAssets += _amount;
        return _amount;
    }

    function convertToAssets(uint256 _shares) public view returns (uint256) {
        if (_shares == 0) return 0;
        if (totalSupply == 0) return 0;
        return (_shares * totalAssets) / totalSupply;
    }

    function convertToShares(uint256 _shares) public view returns (uint256) {
        if (_shares == 0) return 0;
        if (totalSupply == 0) return 0;
        return (_shares * totalSupply) / totalAssets;
    }
}
