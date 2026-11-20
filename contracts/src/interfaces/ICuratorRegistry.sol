// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct Curator {
    string name;
    string metadataURI; // can be a data: URI
    uint40 registeredAt;
    bool active;
}

interface ICuratorRegistry {
    event CuratorRegistered(address indexed curator, string name, string metadataURI);
    event CuratorUpdated(address indexed curator, string metadataURI);

    error AlreadyRegistered();
    error NotRegistered();
    error InvalidName();
    error NameTaken();

    function register(string calldata name, string calldata metadataURI) external;
    function update(string calldata metadataURI) external;
    function isCurator(address account) external view returns (bool);
    function getCurator(address account) external view returns (Curator memory);
    function allCurators() external view returns (address[] memory);
    function curatorCount() external view returns (uint256);
}
