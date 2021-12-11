// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { SafeERC721 } from "./SafeERC721.sol";

contract TipsImpl is ERC721Holder, ERC20, ReentrancyGuard
{
	using SafeERC20 for IERC20;
	using SafeERC721 for IERC721;
	using SafeERC721 for IERC721Metadata;
	using Strings for uint256;

	address public target;
	uint256 public tokenId;
	uint256 public tipsCount;
	uint256 public tipPrice;
	address public paymentToken;

	bool public released;

	string private name_;
	string private symbol_;

	constructor () ERC20("Tips", "FRAC") public
	{
		target = address(-1); // prevents proxy code from misuse
	}

	function __name() public view /*override*/ returns (string memory _name) // rename to name() and change name() on ERC20 to virtual to be able to override on deploy
	{
		if (bytes(name_).length != 0) return name_;
		return string(abi.encodePacked(IERC721Metadata(target).safeName(), " #", tokenId.toString(), " Tips"));
	}

	function __symbol() public view /*override*/ returns (string memory _symbol) // rename to name() and change name() on ERC20 to virtual to be able to override on deploy
	{
		if (bytes(symbol_).length != 0) return symbol_;
		return string(abi.encodePacked(IERC721Metadata(target).safeSymbol(), tokenId.toString()));
	}

	function initialize(address _from, address _target, uint256 _tokenId, string memory _name, string memory _symbol, uint8 _decimals, uint256 _tipsCount, uint256 _tipPrice, address _paymentToken) external
	{
		require(target == address(0), "already initialized");
		require(IERC721(_target).ownerOf(_tokenId) == address(this), "token not staked");
		require(_tipsCount > 0, "invalid tip count");
		require(_tipsCount * _tipPrice / _tipsCount == _tipPrice, "invalid tip price");
		require(_paymentToken != address(this), "invalid token");
		target = _target;
		tokenId = _tokenId;
		tipsCount = _tipsCount;
		tipPrice = _tipPrice;
		paymentToken = _paymentToken;
		released = false;
		name_ = _name;
		symbol_ = _symbol;
		_setupDecimals(_decimals);
		_mint(_from, _tipsCount);
	}

	function status() external view returns (string memory _status)
	{
		return released ? "SOLD" : "OFFER";
	}

	function reservePrice() public view returns (uint256 _reservePrice)
	{
		return tipsCount * tipPrice;
	}

	function redeemAmountOf(address _from) public view returns (uint256 _redeemAmount)
	{
		require(!released, "token already redeemed");
		uint256 _tipsCount = balanceOf(_from);
		uint256 _reservePrice = reservePrice();
		return _reservePrice - _tipsCount * tipPrice;
	}

	function vaultBalance() external view returns (uint256 _vaultBalance)
	{
		if (!released) return 0;
		uint256 _tipsCount = totalSupply();
		return _tipsCount * tipPrice;
	}

	function vaultBalanceOf(address _from) public view returns (uint256 _vaultBalanceOf)
	{
		if (!released) return 0;
		uint256 _tipsCount = balanceOf(_from);
		return _tipsCount * tipPrice;
	}

	function redeem() external payable nonReentrant
	{
		address payable _from = msg.sender;
		uint256 _value = msg.value;
		require(!released, "token already redeemed");
		uint256 _tipsCount = balanceOf(_from);
		uint256 _redeemAmount = redeemAmountOf(_from);
		released = true;
		if (_tipsCount > 0) _burn(_from, _tipsCount);
		_safeTransferFrom(paymentToken, _from, _value, payable(address(this)), _redeemAmount);
		IERC721(target).safeTransfer(_from, tokenId);
		emit Redeem(_from, _tipsCount, _redeemAmount);
		_cleanup();
	}

	function claim() external nonReentrant
	{
		address payable _from = msg.sender;
		require(released, "token not redeemed");
		uint256 _tipsCount = balanceOf(_from);
		require(_tipsCount > 0, "nothing to claim");
		uint256 _claimAmount = vaultBalanceOf(_from);
		_burn(_from, _tipsCount);
		_safeTransfer(paymentToken, _from, _claimAmount);
		emit Claim(_from, _tipsCount, _claimAmount);
		_cleanup();
	}

	function _cleanup() internal
	{
		uint256 _tipsCount = totalSupply();
		if (_tipsCount == 0) {
			selfdestruct(address(0));
		}
	}

	function _safeTransfer(address _token, address payable _to, uint256 _amount) internal
	{
		if (_token == address(0)) {
			_to.transfer(_amount);
		} else {
			IERC20(_token).safeTransfer(_to, _amount);
		}
	}

	function _safeTransferFrom(address _token, address payable _from, uint256 _value, address payable _to, uint256 _amount) internal
	{
		if (_token == address(0)) {
			require(_value == _amount, "invalid value");
			if (_to != address(this)) _to.transfer(_amount);
		} else {
			require(_value == 0, "invalid value");
			IERC20(_token).safeTransferFrom(_from, _to, _amount);
		}
	}

	event Redeem(address indexed _from, uint256 _tipsCount, uint256 _redeemAmount);
	event Claim(address indexed _from, uint256 _tipsCount, uint256 _claimAmount);
}
