// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Dividend Distribution Token
 * Distributes dividends to eligible holders based on their balance
 */
abstract contract DividendDistributingERC20 is ERC20 {
    uint256 internal _dividendPerEligibleToken;
    mapping(address => uint256) internal _accountDividendPerTokenPaid;
    mapping(address => uint256) internal _dividendsEarned;

    uint256 internal _totalDividendEligibleSupply;
    mapping(address => uint256) internal _dividendEligibleBalances;
    mapping(address => bool) internal _dividendEligibleAddress;

    uint256 public scalar;

    event DividendDelivered(uint256 amount);
    event DividendClaimed(address indexed account, uint256 amount);

    constructor(uint8 _scalar) {
        scalar = 10 ** _scalar;
    }

    receive() external payable virtual {
        _registerDividendDelivery(msg.value);
    }

    /// VIEW FUNCTIONS

    function totalDividendEligibleSupply() external view virtual returns (uint256) {
        return _totalDividendEligibleSupply;
    }

    function dividendEligibleBalanceOf(address account) external view virtual returns (uint256) {
        return _dividendEligibleBalances[account];
    }

    function isDividendEligible(address account) external view virtual returns (bool) {
        return _dividendEligibleAddress[account];
    }

    function earned(address account) public view virtual returns (uint256) {
        return _dividendsEarned[account] + 
            (
                _dividendEligibleBalances[account] * 
                (_dividendPerEligibleToken - _accountDividendPerTokenPaid[account]) / 
                scalar
            );
    }

    /// INTERNAL FUNCTIONS

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        /// First time transfer to address with code size 0 will register as eligible
        /// Contract addresses will have code size 0 before and during construction
        /// Any method that sends this token to that address during its construction will make that contract eligible
        /// Self-minting in this contracts constructor makes this contract eligible
        if (_dividendEligibleAddress[to]) {
            _increaseDividendEligibleBalance(to, amount);
        } else {
            if (to.code.length == 0 && to != address(0)) { 
                _increaseDividendEligibleBalance(to, amount);
                _dividendEligibleAddress[to] = true;
            }
        }

        if (_dividendEligibleAddress[from]) { 
            _updateDividend(from);
            _totalDividendEligibleSupply -= amount;
            _dividendEligibleBalances[from] -= amount;
        }
    }

    function _increaseDividendEligibleBalance(address to, uint256 amount) internal virtual {
        _updateDividend(to);
        _totalDividendEligibleSupply += amount;
        _dividendEligibleBalances[to] += amount;
    }

    function _updateDividend(address account) internal virtual {
        _dividendsEarned[account] = earned(account);
        _accountDividendPerTokenPaid[account] = _dividendPerEligibleToken;
    }

    function _registerDividendDelivery(uint256 dividendAmount) internal virtual {
        _dividendPerEligibleToken += dividendAmount * scalar / _totalDividendEligibleSupply;

        emit DividendDelivered(dividendAmount);
    }

    function _transferEth(address to, uint256 amount) internal virtual {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "DividendDistributingERC20: Unable to transfer ETH, recipient may have reverted");
    }

    function getDividend() public virtual {
        uint256 dividend = earned(msg.sender);
        if (dividend > 0) {
            _dividendsEarned[msg.sender] = 0;
            _accountDividendPerTokenPaid[msg.sender] = _dividendPerEligibleToken;
            _transferEth(msg.sender, dividend);

            emit DividendClaimed(msg.sender, dividend);
        }
    }
}
