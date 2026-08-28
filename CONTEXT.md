# Hacker Game

A real-multiplayer browser game, in the spirit of the legacy Hacker Experience, where each Player owns a Computer they use to hack other Players' Computers, steal currency, and cover their tracks.

## Language

**Player**:
A registered account that owns exactly one Computer and one set of currency holdings.
_Avoid_: Hacker, User (both are used loosely for this in casual conversation, but the account is the Player)

**Computer**:
The machine a Player owns: the installed Hardware and Software live on it, it has an IP Address, and it is the thing another Player's Hack targets.
_Avoid_: PC, machine, rig

**IP Address**:
The unique identifier of a Computer, used to target it for a Hack.

**Hardware**:
A component (CPU, RAM, HD, Net) a Player owns and can install into a Slot on their Computer; while installed, it bounds how fast or how much that Computer's Processes can do. A Player may own Hardware they haven't installed.
_Avoid_: specs, parts

**Slot**:
One of a Computer's four fixed Hardware categories (CPU, RAM, HD, Net). At most one Hardware unit can be installed per Slot at a time.
_Avoid_: hardware type, category

**Software**:
A program a Player owns and can run on their Computer to carry out or defend against a Hack (e.g. a cracker, a firewall, a log deleter).
_Avoid_: tool, program (when a more specific Software name is meant, use it)

**Process**:
An asynchronous, timed action a Computer runs (cracking a password, hacking, deleting a Log, etc.). A Process resolves lazily: nothing computes its completion in the background: it's only settled when its state is next read, against its recorded end time.
_Avoid_: job, task

**Hack**:
A Process, run from one Player's Computer against a Target's IP Address, that attempts to gain unauthorized access.

**Target**:
The Computer being hacked, from the perspective of a given Hack.

**Connection**:
The state of a Player's Computer having successfully hacked into a Target, during which further Processes (stealing currency, deleting a Log) can be run against it. Ends when the attacker disconnects.
_Avoid_: session (reserved for auth sessions)

**Dinheiro**:
The traceable currency, held in a Bank Account. Movements involving Dinheiro produce a Log entry the Target can see.
_Avoid_: money, cash, dollars

**HackerCoin**:
The untraceable currency, held in a Wallet. Movements involving HackerCoin produce no Log entry.
_Avoid_: crypto, bitcoin, HC

**Bank Account**:
Where a Player's Dinheiro is held.

**Wallet**:
Where a Player's HackerCoin is held.

**Log**:
A record left on a Computer of an action taken against or from it. Visible to that Computer's Player. The Player who caused an entry can remove it via a log-deletion Process, but only while still connected: it isn't removable after they disconnect.
_Avoid_: history, activity feed, audit trail
