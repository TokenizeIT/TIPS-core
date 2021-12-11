// Processor / ERC721Processor
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/EnumerableSet.sol";

import { SafeERC721Metadata } from "./SafeERC721Metadata.sol";
import { ERC721Dividends } from "./Dividends.sol";

library Processor
{
	using SafeERC721Metadata for IERC721Metadata;

	function create(IERC721 _target) public returns (ERC721Processor _processor)
	{
		IERC721Metadata _metadata = IERC721Metadata(address(_target));
		string memory _name = string(abi.encodePacked("Wrapped ", _metadata.safeName()));
		string memory _symbol = string(abi.encodePacked("w", _metadata.safeSymbol()));
		return new ERC721Processor(_name, _symbol, _target);
	}
}

contract ERC721Processor is Ownable, ERC721
{
	using SafeERC721Metadata for IERC721Metadata;
	using EnumerableSet for EnumerableSet.AddressSet;

	IERC721 public immutable target;
	mapping (uint256 => ERC721Dividends) public dividends;
	EnumerableSet.AddressSet private history;

	constructor (string memory _name, string memory _symbol, IERC721 _target) ERC721(_name, _symbol) public
	{
		target = _target;
	}

	function securitized(uint256 _tokenId) external view returns (bool _securitized)
	{
		return dividends[_tokenId] != ERC721Dividends(0);
	}

	function historyLength() external view returns (uint256 _length)
	{
		return history.length();
	}

	function historyAt(uint256 _index) external view returns (ERC721Dividends _dividends)
	{
		return ERC721Dividends(history.at(_index));
	}

	function _insert(address _from, uint256 _tokenId, bool _remnant, ERC721Dividends _dividends) external onlyOwner
	{
		assert(dividends[_tokenId] == ERC721Dividends(0));
		dividends[_tokenId] = _dividends;
		assert(history.add(address(_dividends)));
		address _holder = _remnant ? _from : address(_dividends);
		_safeMint(_holder, _tokenId);
		IERC721Metadata _metadata = IERC721Metadata(address(target));
		string memory _tokenURI = _metadata.safeTokenURI(_tokenId);
		_setTokenURI(_tokenId, _tokenURI);
	}

	function _remove(address _from, uint256 _tokenId, bool _remnant) external
	{
		ERC721Dividends _dividends = ERC721Dividends(msg.sender);
		assert(dividends[_tokenId] == _dividends);
		dividends[_tokenId] = ERC721Dividends(0);
		address _holder = _remnant ? _from : address(_dividends);
		assert(_holder == ownerOf(_tokenId));
		_burn(_tokenId);
	}

	function _forget() external
	{
		ERC721Dividends _dividends = ERC721Dividends(msg.sender);
		assert(history.remove(address(_dividends)));
	}
}
