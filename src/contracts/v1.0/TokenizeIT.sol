// TokenizeIT
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Processor, ERC721Processor } from "./Processor.sol";
import { Dividends, ERC721Dividends } from "./Dividends.sol";

contract TokenizeIT is ReentrancyGuard
{
	mapping (IERC721 => bool) private wraps;
	mapping (IERC721 => ERC721Processor) public processors;

	function ensureProcessor(IERC721 _target) internal returns (ERC721Processor _processor)
	{
		require(!wraps[_target], "cannot wrap a processor");
		_processor = processors[_target];
		if (_processor == ERC721Processor(0)) {
			_processor = Processor.create(_target);
			processors[_target] = _processor;
			wraps[_processor] = true;
		}
		return _processor;
	}

	function securitize(IERC721 _target, uint256 _tokenId, uint256 _dividendsCount, uint8 _decimals, uint256 _exitPrice, IERC20 _paymentToken, bool _remnant) external nonReentrant
	{
		address _from = msg.sender;
		ERC721Processor _processor = ensureProcessor(_target);
		require(_exitPrice > 0, "invalid exit price");
		require(_dividendsCount > 0, "invalid dividends count");
		require(_exitPrice % _dividendsCount == 0, "fractional price per share");
		uint256 _sharePrice = _exitPrice / _dividendsCount;
		ERC721Dividends _dividends = Dividends.create(_processor, _tokenId, _from, _dividendsCount, _decimals, _sharePrice, _paymentToken, _remnant);
		_target.transferFrom(_from, address(_dividends), _tokenId);
		_processor._insert(_from, _tokenId, _remnant, _dividends);
	}
}
