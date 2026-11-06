// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ISqueekCore, ISqueekNFT, ISqueekStaking} from "./interfaces/ISqueek.sol";
import {Reading} from "./Types.sol";
import {OdometerArt} from "./art/OdometerArt.sol";

/// @title Squeek Odometer
/// @notice A free, fully on-chain odometer for Squeektoshi, the hamster whose wheel powers Squeekchain. Each token
/// remembers the wheel's settled work when it was minted and shows how far he has run since, read live from
/// SqueekCore. No owner, no admin, no upgrade, no funds.
contract SqueekOdometer is ERC721 {
    uint256 public constant MAX_SUPPLY = 9_999;
    /// @notice Wheel distance per work unit. The device estimates distance from a fixed wheel circumference; its
    /// lifetime figures (22,789,368 mm over 25,701 units) give 886.7 mm, live speed/RPM readings about 880 mm.
    uint256 public constant MM_PER_WORK = 887;
    /// @notice Work over the last three settled rounds (30 minutes) at or above which he has the zoomies.
    uint256 public constant ZOOMIES_WORK = 1_500;
    uint8 public constant NAPPING = 0;
    uint8 public constant JOGGING = 1;
    uint8 public constant ZOOMIES = 2;
    uint8 public constant UNKNOWN = 3;
    /// @dev Gas each read of a Squeekchain contract may use: a broken or hostile dependency can only fail its read.
    uint256 internal constant READ_GAS = 500_000;
    /// @dev The ABI offset a static call returning one dynamic struct starts with.
    uint256 internal constant HEAD = 0x20;

    ISqueekCore public immutable core;
    ISqueekNFT public immutable squeeks;
    ISqueekStaking public immutable staking;

    uint256 public totalMinted;
    /// @notice The token a wallet minted (0: none). A wallet mints once, even after it sends its token away.
    mapping(address => uint256) public idOf;
    mapping(uint256 => uint256) public startWork;
    mapping(uint256 => uint256) public mintedAt;

    event Minted(uint256 indexed id, address indexed to, uint256 startWork);
    /// @notice ERC-4906: the art changed. The art changes on its own as the wheel turns, but marketplaces cache
    /// images, so anyone can ask them to look again.
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    error AlreadyMinted();
    error SoldOut();
    error CoreUnreadable();

    /// @dev No external calls and no chain check: the launch rehearses this constructor on an empty chain whose id is
    /// not Sepolia's, and it must deploy there. The Sepolia binding is the three addresses, not the chain id.
    constructor(address core_, address squeeks_, address staking_) ERC721("Squeek Odometer", "ODOMETER") {
        core = ISqueekCore(core_);
        squeeks = ISqueekNFT(squeeks_);
        staking = ISqueekStaking(staking_);
    }

    /// @notice Free, one per wallet. The odometer starts from the wheel's settled work right now.
    function mint() external returns (uint256 id) {
        if (idOf[msg.sender] != 0) revert AlreadyMinted();
        if (totalMinted >= MAX_SUPPLY) revert SoldOut();
        (bool ok, uint256[8] memory s) = _read(address(core), abi.encodeCall(ISqueekCore.state, ()), 2);
        // a token must start from a real reading: both words are uint64 in CoreState, and a baseline no canonical
        // reading could ever exceed would freeze the token at 0 for good (there is no owner to correct it)
        if (!ok || !_fits64(s[0]) || !_fits64(s[1])) revert CoreUnreadable();
        id = ++totalMinted;
        idOf[msg.sender] = id;
        startWork[id] = s[1];
        mintedAt[id] = block.timestamp;
        _mint(msg.sender, id);
        emit Minted(id, msg.sender, s[1]);
    }

    /// @notice What token `id` shows now. Reverts for a token that does not exist.
    function reading(uint256 id) public view returns (Reading memory r) {
        address owner = _requireOwned(id);
        r.startWork = startWork[id];
        // the token's own odometer, fixed at mint: display, casing and the treat he holds, rolled from its id and
        // its starting work
        uint256 h = uint256(keccak256(abi.encode(id, r.startWork)));
        r.display = OdometerArt.displayOf(h % 100);
        r.casing = OdometerArt.casingOf((h >> 64) % 100);
        r.pouch = OdometerArt.pouchOf((h >> 128) % 100);
        // CoreState is static: settledThroughRound, cumulativeWork, cumulativeBlockUnits, blockHeight, ... A word
        // outside the uint64 its field declares is not a reading (an upgraded or hostile core), so it fails like a
        // revert would, and the metadata degrades to unknown instead of overflowing.
        (bool ok, uint256[8] memory s) = _read(address(core), abi.encodeCall(ISqueekCore.state, ()), 4);
        if (ok && _fits64(s[0]) && _fits64(s[1]) && _fits64(s[3])) {
            r.live = true;
            r.work = s[1] > r.startWork ? s[1] - r.startWork : 0;
            r.blockHeight = uint64(s[3]);
            (r.status, r.pace) = _status(uint64(s[0]));
        } else {
            r.status = UNKNOWN;
        }
        r.distanceMm = r.work * MM_PER_WORK;
        r.stage = stageOf(r.distanceMm);
        r.tier = _tier(owner);
        r.holder = r.tier > 0;
    }

    /// @notice Metadata and art, rendered from the live reading on every call (nothing is stored but the start).
    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("data:application/json;base64,", Base64.encode(OdometerArt.json(id, reading(id))));
    }

    /// @notice Ask marketplaces to fetch token `id` again (free for anyone; it changes nothing but the event log).
    function refresh(uint256 id) external {
        _requireOwned(id);
        emit MetadataUpdate(id);
    }

    /// @notice The same for every token.
    function refreshAll() external {
        if (totalMinted > 0) emit BatchMetadataUpdate(1, totalMinted);
    }

    /// @notice ERC-4906 too: the art changes on its own, so marketplaces should refresh it.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == 0x49064906 || super.supportsInterface(interfaceId);
    }

    /// @notice Stage for a distance: 0 Newbie, 1 Warm-up (1 km), 2 Jogger (5), 3 Runner (10), 4 Racer (25),
    /// 5 Marathoner (50), 6 Legend (100 km).
    function stageOf(uint256 distanceMm) public pure returns (uint8 stage) {
        uint32[6] memory km = [uint32(1), 5, 10, 25, 50, 100];
        for (uint256 i; i < 6; i++) {
            if (distanceMm < uint256(km[i]) * 1_000_000) return stage;
            stage++;
        }
    }

    /// @dev Napping, jogging or zoomies from the work settled in the last three rounds (up to `settled`), and that work.
    function _status(uint64 settled) internal view returns (uint8, uint256) {
        if (settled == 0) return (NAPPING, 0);
        uint64 from = settled > 3 ? settled - 3 : 0;
        // RoundPage is dynamic: [offset, certifiedThroughRound, start(cumulativeWork, ..), end(cumulativeWork, ..)];
        // an answer that does not start at that offset, or whose work words exceed their uint64, is not a page
        (bool ok, uint256[8] memory p) =
            _read(address(core), abi.encodeCall(ISqueekCore.roundPage, (from, settled, 3)), 6);
        if (!ok || p[0] != HEAD || !_fits64(p[2]) || !_fits64(p[5])) return (UNKNOWN, 0);
        uint256 w = p[5] > p[2] ? p[5] - p[2] : 0;
        if (w == 0) return (NAPPING, 0);
        return (w >= ZOOMIES_WORK ? ZOOMIES : JOGGING, w);
    }

    /// @dev The holder's frame from Squeek power deposited in staking (Squeekchain's base power per level: L3 4,840,
    /// L5 23,426, L7 113,380, at 1e18): diamond, gold, silver, else bronze; a Squeek only in the wallet (no power: its
    /// level cannot be read without its id) is bronze. Staking owns deposited Squeeks, so their wallet holds 0.
    function _tier(address who) internal view returns (uint8) {
        (bool ok, uint256[8] memory b) = _read(address(staking), abi.encodeCall(ISqueekStaking.accountPower, (who)), 1);
        if (ok && b[0] > 0) {
            if (b[0] >= 113_380e18) return 4;
            if (b[0] >= 23_426e18) return 3;
            if (b[0] >= 4_840e18) return 2;
            return 1;
        }
        (ok, b) = _read(address(squeeks), abi.encodeCall(ISqueekNFT.balanceOf, (who)), 1);
        return ok && b[0] > 0 ? 1 : 0;
    }

    /// @dev Whether a copied word is a valid encoding of the uint64 its field declares.
    function _fits64(uint256 word) internal pure returns (bool) {
        return word <= type(uint64).max;
    }

    /// @dev A gas-capped static call that copies at most `words` words of the answer (no return-data bomb) and fails
    /// unless the answer has at least that many.
    function _read(address to, bytes memory data, uint256 words) internal view returns (bool ok, uint256[8] memory w) {
        assembly ("memory-safe") {
            ok := staticcall(READ_GAS, to, add(data, 0x20), mload(data), w, mul(words, 0x20))
            if lt(returndatasize(), mul(words, 0x20)) { ok := 0 }
        }
    }
}
