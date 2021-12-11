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

contract AuctionTipsImpl is ERC721Holder, ERC20, ReentrancyGuard
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
	uint256 public kickoff;
	uint256 public duration;
	uint256 public fee;
	address public vault;

	bool public released;
	uint256 public cutoff;
	address payable public bidder;

	uint256 private lockedTips_;
	uint256 private lockedAmount_;

	string private name_;
	string private symbol_;

	constructor () ERC20("Tips", "TIPS") public
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

	modifier onlyOwner()
	{
		require(isOwner(msg.sender), "access denied");
		_;
	}

	modifier onlyHolder()
	{
		require(balanceOf(msg.sender) > 0, "access denied");
		_;
	}

	modifier onlyBidder()
	{
		require(msg.sender == bidder, "access denied");
		_;
	}

	modifier inAuction()
	{
		require(kickoff <= now && now <= cutoff, "not available");
		_;
	}

	modifier afterAuction()
	{
		require(now > cutoff, "not available");
		_;
	}

	function initialize(address _from, address _target, uint256 _tokenId, string memory _name, string memory _symbol, uint8 _decimals, uint256 _tipsCount, uint256 _tipPrice, address _paymentToken, uint256 _kickoff, uint256 _duration, uint256 _fee, address _vault) external
	{
		require(target == address(0), "already initialized");
		require(IERC721(_target).ownerOf(_tokenId) == address(this), "missing token");
		require(_tipsCount > 0, "invalid count");
		require(_tipsCount * _tipPrice / _tipsCount == _tipPrice, "price overflow");
		require(_paymentToken != address(this), "invalid token");
		require(_kickoff <= now + 731 days, "invalid kickoff");
		require(30 minutes <= _duration && _duration <= 731 days, "invalid duration");
		require(_fee <= 1e18, "invalid fee");
		require(_vault != address(0), "invalid address");
		target = _target;
		tokenId = _tokenId;
		tipsCount = _tipsCount;
		tipPrice = _tipPrice;
		paymentToken = _paymentToken;
		kickoff = _kickoff;
		duration = _duration;
		fee = _fee;
		vault = _vault;
		released = false;
		cutoff = uint256(-1);
		bidder = address(0);
		name_ = _name;
		symbol_ = _symbol;
		_setupDecimals(_decimals);
		uint256 _feeTipsCount = _tipsCount.mul(_fee) / 1e18;
		uint256 _netTipsCount = _tipsCount - _feeTipsCount;
		_mint(_from, _netTipsCount);
		_mint(address(this), _feeTipsCount);
		lockedTips_ = _feeTipsCount;
		lockedAmount_ = 0;
	}

	function status() external view returns (string memory _status)
	{
		return bidder == address(0) ? now < kickoff ? "PAUSE" : "OFFER" : now > cutoff ? "SOLD" : "AUCTION";
	}

	function isOwner(address _from) public view returns (bool _soleOwner)
	{
		return bidder == address(0) && balanceOf(_from) + lockedTips_ == tipsCount;
	}

	function reservePrice() external view returns (uint256 _reservePrice)
	{
		return tipsCount * tipPrice;
	}

	function bidRangeOf(address _from) external view inAuction returns (uint256 _minTipPrice, uint256 _maxTipPrice)
	{
		if (bidder == address(0)) {
			_minTipPrice = tipPrice;
		} else {
			_minTipPrice = (tipPrice * 11 + 9) / 10; // 10% increase, rounded up
		}
		uint256 _tipsCount = balanceOf(_from);
		if (bidder == _from) _tipsCount += lockedTips_;
		if (_tipsCount == 0) {
			_maxTipPrice = uint256(-1);
		} else {
			_maxTipPrice = _minTipPrice + (tipsCount * tipsCount * tipPrice) / (_tipsCount * _tipsCount * 100); // 1% / (ownership ^ 2)
		}
		return (_minTipPrice, _maxTipPrice);
	}

	function bidAmountOf(address _from, uint256 _newTipPrice) external view inAuction returns (uint256 _bidAmount)
	{
		uint256 _tipsCount = balanceOf(_from);
		if (bidder == _from) _tipsCount += lockedTips_;
		return (tipsCount - _tipsCount) * _newTipPrice;
	}

	function vaultBalance() external view returns (uint256 _vaultBalance)
	{
		if (now <= cutoff) return 0;
		uint256 _tipsCount = totalSupply();
		return _tipsCount * tipPrice;
	}

	function vaultBalanceOf(address _from) external view returns (uint256 _vaultBalanceOf)
	{
		if (now <= cutoff) return 0;
		uint256 _tipsCount = balanceOf(_from);
		return _tipsCount * tipPrice;
	}

	function updatePrice(uint256 _newTipPrice) external onlyOwner
	{
		address _from = msg.sender;
		require(tipsCount * _newTipPrice / tipsCount == _newTipPrice, "price overflow");
		uint256 _oldTipPrice = tipPrice;
		tipPrice = _newTipPrice;
		emit UpdatePrice(_from, _oldTipPrice, _newTipPrice);
	}

	function cancel() external nonReentrant onlyOwner
	{
		address _from = msg.sender;
		released = true;
		_burn(_from, balanceOf(_from));
		_burn(address(this), lockedTips_);
		IERC721(target).safeTransfer(_from, tokenId);
		emit Cancel(_from);
		_cleanup();
	}

	function bid(uint256 _newTipPrice) external payable nonReentrant inAuction
	{
		address payable _from = msg.sender;
		uint256 _value = msg.value;
		require(tipsCount * _newTipPrice / tipsCount == _newTipPrice, "price overflow");
		uint256 _oldTipPrice = tipPrice;
		uint256 _tipsCount;
		if (bidder == address(0)) {
			_transfer(address(this), vault, lockedTips_);
			_tipsCount = balanceOf(_from);
			uint256 _tipsCount2 = _tipsCount * _tipsCount;
			require(_newTipPrice >= _oldTipPrice, "below minimum");
			require(_newTipPrice * _tipsCount2 * 100 <= _oldTipPrice * (_tipsCount2 * 100 + tipsCount * tipsCount), "above maximum"); // <= 1% / (ownership ^ 2)
			cutoff = now + duration;
		} else {
			if (lockedTips_ > 0) _transfer(address(this), bidder, lockedTips_);
			_safeTransfer(paymentToken, bidder, lockedAmount_);
			_tipsCount = balanceOf(_from);
			uint256 _tipsCount2 = _tipsCount * _tipsCount;
			require(_newTipPrice * 10 >= _oldTipPrice * 11, "below minimum"); // >= 10%
			require(_newTipPrice * _tipsCount2 * 100 <= _oldTipPrice * (_tipsCount2 * 110 + tipsCount * tipsCount), "above maximum"); // <= 10% + 1% / (ownership ^ 2)
			if (cutoff < now + 15 minutes) cutoff = now + 15 minutes;
		}
		bidder = _from;
		tipPrice = _newTipPrice;
		uint256 _bidAmount = (tipsCount - _tipsCount) * _newTipPrice;
		if (_tipsCount > 0) _transfer(_from, address(this), _tipsCount);
		_safeTransferFrom(paymentToken, _from, _value, payable(address(this)), _bidAmount);
		lockedTips_ = _tipsCount;
		lockedAmount_ = _bidAmount;
		emit Bid(_from, _oldTipPrice, _newTipPrice, _tipsCount, _bidAmount);
	}

	function redeem() external nonReentrant onlyBidder afterAuction
	{
		address _from = msg.sender;
		require(!released, "missing token");
		released = true;
		_burn(address(this), lockedTips_);
		IERC721(target).safeTransfer(_from, tokenId);
		emit Redeem(_from);
		_cleanup();
	}

	function claim() external nonReentrant onlyHolder afterAuction
	{
		address payable _from = msg.sender;
		uint256 _tipsCount = balanceOf(_from);
		uint256 _claimAmount = _tipsCount * tipPrice;
		_burn(_from, _tipsCount);
		_safeTransfer(paymentToken, _from, _claimAmount);
		emit Claim(_from, _tipsCount, _claimAmount);
		_cleanup();
	}

	function _cleanup() internal
	{
		uint256 _tipsCount = totalSupply();
		if (released && _tipsCount == 0) {
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

	event UpdatePrice(address indexed _from, uint256 _oldTipPrice, uint256 _newTipPrice);
	event Cancel(address indexed _from);
	event Bid(address indexed _from, uint256 _oldTipPrice, uint256 _newTipPrice, uint256 _tipsCount, uint256 _bidAmount);
	event Redeem(address indexed _from);
	event Claim(address indexed _from, uint256 _tipsCount, uint256 _claimAmount);
}
