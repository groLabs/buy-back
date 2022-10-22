// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface seller {
    sellToken(address _token) external;
}

contract buyBack {

    address[] public tokens;
    address owner;
    address keeper;
    address keeperWallet;
    address treasury;
    address burner;
    address vestor;

    struct distributionSplit {
        uint256 treasury;
        uint256 burner;
        uint256 keeper;
    }

    mapping(address => distributionSplit) tokenDistribution;

    event LogNewTokenAdded(address token);
    event LogNewTokenRemoved(address token);
    event LogDepositReceived(address sender, uint256 amount);

    function setTokenDistribution(address _token, uint256 _treasury, uint256 _burner, uint256 _keeper) {

    }

    function setToken(address _token) external {
        if(msg.sender != owner) revert;
        tokens.push(_token);
        emit LogNewTokenAdded(_token);
    }

    function removeToken(address _token, address _target, bool _wrapped) external {
        if(msg.sender != owner) revert;

        uint256 noOfTokens = tokens.length;
        for (uint256 i = 0; i < noOfTokens - 1; i++) {
            if(tokens[i] == _token) {
                tokens[i] = tokens[noOfTokens - 1];
                tokens.pop();
            }
        }
        emit LogTokenRemoved(_token);
    }

    function sellTokens() external {
        if(msg.sender != owner || msg.sender != keeper) revert;

    }

    function topUpKeeper() external view returns (uint256) {

    }

    function sendToTreasury() external view returns (uint256) {

    }

    function burnTokens() external view returns (uint256) {

    }

    function() payable {
        require(msg.data.length == 0);
        emit LogDepositReceived(msg.sender, msg.value); 
    }
}
