// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { AuctionTips } from "./AuctionTips.sol";
import { AuctionTipsImpl } from "./AuctionTipsImpl.sol";

contract AuctionFractionalizer is ReentrancyGuard
{
	address public immutable vault;

	constructor (address _vault) public
	{
		vault = _vault;
	}

	function fractionalize(address _target, uint256 _tokenId, string memory _name, string memory _symbol, uint8 _decimals, uint256 _tipsCount, uint256 _tipPrice, address _paymentToken, uint256 _kickoff, uint256 _duration, uint256 _fee) external nonReentrant returns (address _tips)
	{
		address _from = msg.sender;
		_tips = address(new AuctionTips());
		IERC721(_target).transferFrom(_from, _tips, _tokenId);
		AuctionTipsImpl(_tips).initialize(_from, _target, _tokenId, _name, _symbol, _decimals, _tipsCount, _tipPrice, _paymentToken, _kickoff, _duration, _fee, vault);
		emit Fractionalize(_from, _target, _tokenId, _tips);
		return _tips;
	}

	event Fractionalize(address indexed _from, address indexed _target, uint256 indexed _tokenId, address _tips);
}
