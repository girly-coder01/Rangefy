// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ICuratorRegistry, Curator} from "../interfaces/ICuratorRegistry.sol";

/// @title CuratorRegistry
/// @notice Permissionless registry of strategy curators.
/// @dev Names: 3-32 chars of [A-Za-z0-9 _-], unique ignoring case.
contract CuratorRegistry is ICuratorRegistry {
    mapping(address => Curator) internal _curators;
    mapping(bytes32 => address) public nameOwner; // keccak(lowercased name)
    address[] internal _all;

    function register(string calldata name, string calldata metadataURI) external {
        if (_curators[msg.sender].registeredAt != 0) revert AlreadyRegistered();
        bytes32 key = _nameKey(name);
        if (nameOwner[key] != address(0)) revert NameTaken();

        nameOwner[key] = msg.sender;
        _curators[msg.sender] =
            Curator({name: name, metadataURI: metadataURI, registeredAt: uint40(block.timestamp), active: true});
        _all.push(msg.sender);
        emit CuratorRegistered(msg.sender, name, metadataURI);
    }

    function update(string calldata metadataURI) external {
        Curator storage c = _curators[msg.sender];
        if (c.registeredAt == 0) revert NotRegistered();
        c.metadataURI = metadataURI;
        emit CuratorUpdated(msg.sender, metadataURI);
    }

    function isCurator(address account) external view returns (bool) {
        return _curators[account].active;
    }

    function getCurator(address account) external view returns (Curator memory) {
        return _curators[account];
    }

    function allCurators() external view returns (address[] memory) {
        return _all;
    }

    function curatorCount() external view returns (uint256) {
        return _all.length;
    }

    function _nameKey(string calldata name) internal pure returns (bytes32) {
        bytes memory b = bytes(name);
        if (b.length < 3 || b.length > 32) revert InvalidName();
        for (uint256 i; i < b.length; ++i) {
            bytes1 ch = b[i];
            if (ch >= 0x41 && ch <= 0x5A) {
                b[i] = bytes1(uint8(ch) + 32);
            } else if (!((ch >= 0x61 && ch <= 0x7A) || (ch >= 0x30 && ch <= 0x39) || ch == 0x20 || ch == 0x5F
                        || ch == 0x2D)) {
                revert InvalidName();
            }
        }
        if (b[0] == 0x20 || b[b.length - 1] == 0x20) revert InvalidName();
        return keccak256(b);
    }
}
