// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UniversityRegistry
 * @notice Registry of verified university addresses for the SimpleGoFundMe platform
 * @dev Maintains a mapping of university symbols to their wallet addresses and details
 */
contract UniversityRegistry is Ownable {
    constructor(address _owner) Ownable(_owner) {}
    /**
     * @dev Struct to store university information
     * @param name Full name of the university
     * @param wallet Verified wallet address of the university
     * @param isActive Whether the university is currently active in the registry
     */
    struct University {
        string name;
        address wallet;
        bool isActive;
    }

    // Mappings to store university data
    mapping(string => University) public universities;     // symbol => University
    mapping(address => string) public walletToSymbol;     // wallet => symbol
    string[] public universitySymbols;                    // Array of all registered symbols

    // Events
    event UniversityAdded(string symbol, string name, address wallet);
    event UniversityUpdated(string symbol, string name, address wallet);
    event UniversityDeactivated(string symbol);
    event UniversityReactivated(string symbol);

    /**
     * @notice Checks if a symbol exists and is active
     * @param symbol University symbol to check
     */
    modifier validUniversity(string memory symbol) {
        require(universities[symbol].wallet != address(0), "University not registered");
        require(universities[symbol].isActive, "University not active");
        _;
    }

    /**
     * @notice Add a new university to the registry
     * @param symbol Short symbol for the university (e.g., "MIT")
     * @param name Full name of the university
     * @param wallet University's wallet address
     */
    function addUniversity(
        string memory symbol,
        string memory name,
        address wallet
    ) external onlyOwner {
        require(bytes(symbol).length > 0, "Empty symbol");
        require(bytes(name).length > 0, "Empty name");
        require(wallet != address(0), "Invalid wallet");
        require(universities[symbol].wallet == address(0), "Symbol already registered");
        require(bytes(walletToSymbol[wallet]).length == 0, "Wallet already registered");

        universities[symbol] = University({
            name: name,
            wallet: wallet,
            isActive: true
        });
        walletToSymbol[wallet] = symbol;
        universitySymbols.push(symbol);

        emit UniversityAdded(symbol, name, wallet);
    }

    /**
     * @notice Update an existing university's details
     * @param symbol University symbol to update
     * @param name New name for the university
     * @param wallet New wallet address
     */
    function updateUniversity(
        string memory symbol,
        string memory name,
        address wallet
    ) external onlyOwner validUniversity(symbol) {
        require(wallet != address(0), "Invalid wallet");
        
        // If wallet address is changing, update the reverse mapping
        if (universities[symbol].wallet != wallet) {
            delete walletToSymbol[universities[symbol].wallet];
            walletToSymbol[wallet] = symbol;
        }

        universities[symbol].name = name;
        universities[symbol].wallet = wallet;

        emit UniversityUpdated(symbol, name, wallet);
    }

    /**
     * @notice Deactivate a university
     * @param symbol University symbol to deactivate
     */
    function deactivateUniversity(string memory symbol) 
        external 
        onlyOwner 
        validUniversity(symbol) 
    {
        universities[symbol].isActive = false;
        emit UniversityDeactivated(symbol);
    }

    /**
     * @notice Reactivate a previously deactivated university
     * @param symbol University symbol to reactivate
     */
    function reactivateUniversity(string memory symbol) 
        external 
        onlyOwner 
    {
        require(universities[symbol].wallet != address(0), "University not registered");
        require(!universities[symbol].isActive, "University already active");
        
        universities[symbol].isActive = true;
        emit UniversityReactivated(symbol);
    }

    /**
     * @notice Get university details by symbol
     * @param symbol University symbol to query
     * @return name University name
     * @return wallet University wallet address
     * @return isActive Whether university is active
     */
    function getUniversity(string memory symbol)
        external
        view
        returns (string memory name, address wallet, bool isActive)
    {
        University memory uni = universities[symbol];
        require(uni.wallet != address(0), "University not found");
        return (uni.name, uni.wallet, uni.isActive);
    }

    /**
     * @notice Get university symbol by wallet address
     * @param wallet Wallet address to query
     * @return symbol University symbol
     */
    function getSymbolByWallet(address wallet)
        external
        view
        returns (string memory symbol)
    {
        string memory sym = walletToSymbol[wallet];
        require(bytes(sym).length > 0, "Wallet not registered");
        return sym;
    }

    /**
     * @notice Check if a wallet address belongs to a registered and active university
     * @param wallet Wallet address to verify
     * @return bool Whether the wallet is valid
     */
    function isValidUniversityWallet(address wallet) 
        external 
        view 
        returns (bool) 
    {
        string memory symbol = walletToSymbol[wallet];
        return bytes(symbol).length > 0 && universities[symbol].isActive;
    }

    /**
     * @notice Get list of all registered university symbols
     * @return Array of university symbols
     */
    function getAllUniversitySymbols() external view returns (string[] memory) {
        return universitySymbols;
    }

    /**
     * @notice Get count of registered universities
     * @return Number of universities in registry
     */
    function getUniversityCount() external view returns (uint256) {
        return universitySymbols.length;
    }
}