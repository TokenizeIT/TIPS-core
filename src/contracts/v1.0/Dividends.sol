// Dividends / ERC721Dividends
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

import { SafeERC721Metadata } from "./SafeERC721Metadata.sol";
import { ERC721Processor } from "./Processor.sol";

library Dividends
{
	using Strings for uint256;
	using SafeERC721Metadata for IERC721Metadata;

	function create(ERC721Processor _processor, uint256 _tokenId, address _from, uint256 _dividendsCount, uint8 _decimals, uint256 _dividendPrice, IERC20 _paymentToken, bool _remnant) public returns (ERC721Dividends _dividends)
	{
		IERC721 _target = _processor.target();
		IERC721Metadata _metadata = IERC721Metadata(address(_target));
		string memory _name = string(abi.encodePacked(_metadata.safeName(), " #", _tokenId.toString(), " Dividends"));
		string memory _symbol = string(abi.encodePacked(_metadata.safeSymbol(), _tokenId.toString()));
		return new ERC721Dividends(_name, _symbol, _processor, _tokenId, _from, _dividendsCount, _decimals, _dividendPrice, _paymentToken, _remnant);
	}
}

contract ERC721Dividends is ERC721Holder, ERC20, ReentrancyGuard
{
	using SafeERC20 for IERC20;

	ERC721Processor public immutable processor;
	uint256 public immutable tokenId;
	uint256 public immutable dividendsCount;
	uint256 public immutable dividendPrice;
	IERC20 public immutable paymentToken;
	bool public immutable remnant;

	bool public released;

	constructor (string memory __name, string memory __symbol, ERC721Processor _processor, uint256 _tokenId, address _from, uint256 _dividendsCount, uint8 _decimals, uint256 _dividendPrice, IERC20 _paymentToken, bool _remnant) ERC20(__name, __symbol) public
	{
		processor = _processor;
		tokenId = _tokenId;
		dividendsCount = _dividendsCount;
		dividendPrice = _dividendPrice;
		paymentToken = _paymentToken;
		remnant = _remnant;
		released = false;
		_setupDecimals(_decimals);
		_mint(_from, _dividendsCount);
		emit Securitize(_from, address(_processor.target()), _tokenId, address(this));
	}

	function exitPrice() public view returns (uint256 _exitPrice)
	{
		return dividendsCount * dividendPrice;
	}

	function redeemAmountOf(address _from) public view returns (uint256 _redeemAmount)
	{
		require(!released, "token already redeemed");
		uint256 _dividendsCount = balanceOf(_from);
		uint256 _exitPrice = exitPrice();
		return _exitPrice - _dividendsCount * dividendPrice;
	}

	function vaultBalance() external view returns (uint256 _vaultBalance)
	{
		if (!released) return 0;
		uint256 _dividendsCount = totalSupply();
		return _dividendsCount * dividendPrice;
	}

	function vaultBalanceOf(address _from) public view returns (uint256 _vaultBalanceOf)
	{
		if (!released) return 0;
		uint256 _dividendsCount = balanceOf(_from);
		return _dividendsCount * dividendPrice;
	}

	function redeem() external payable nonReentrant
	{
		require(!released, "token already redeemed");
		address payable _from = msg.sender;
		uint256 _paymentAmount = msg.value;
		uint256 _dividendsCount = balanceOf(_from);
		uint256 _redeemAmount = redeemAmountOf(_from);
		if (paymentToken == IERC20(0)) {
			require(_paymentAmount >= _redeemAmount, "insufficient payment amount");
			uint256 _changeAmount = _paymentAmount - _redeemAmount;
			if (_changeAmount > 0) _from.transfer(_changeAmount);
		} else {
			if (_paymentAmount > 0) _from.transfer(_paymentAmount);
			if (_redeemAmount > 0) paymentToken.safeTransferFrom(_from, address(this), _redeemAmount);
		}
		released = true;
		if (_dividendsCount > 0) _burn(_from, _dividendsCount);
		processor._remove(_from, tokenId, remnant);
		try processor.target().approve(address(this), tokenId) {
		} catch (bytes memory /* _data */) {
		}
		processor.target().transferFrom(address(this), _from, tokenId);
		emit Redeem(_from, address(processor.target()), tokenId, address(this));
		_cleanup();
	}

	function claim() external nonReentrant
	{
		require(released, "token not redeemed");
		address payable _from = msg.sender;
		uint256 _dividendsCount = balanceOf(_from);
		require(_dividendsCount > 0, "nothing to claim");
		uint256 _claimAmount = vaultBalanceOf(_from);
		assert(_claimAmount > 0);
		_burn(_from, _dividendsCount);
		if (paymentToken == IERC20(0)) _from.transfer(_claimAmount);
		else paymentToken.safeTransfer(_from, _claimAmount);
		emit Claim(_from, address(processor.target()), tokenId, address(this), _dividendsCount);
		_cleanup();
	}

	function _cleanup() internal
	{
		uint256 _dividendsLeft = totalSupply();
		if (_dividendsLeft == 0) {
			processor._forget();
			selfdestruct(address(0));
		}
	}

	event Securitize(address indexed _from, address indexed _target, uint256 indexed _tokenId, address _dividends);
	event Redeem(address indexed _from, address indexed _target, uint256 indexed _tokenId, address _dividends);
	event Claim(address indexed _from, address indexed _target, uint256 indexed _tokenId, address _dividends, uint256 _dividendsCount);
}
