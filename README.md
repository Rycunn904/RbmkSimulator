# RbmkSimulator (Headless & Multiplayer Server Fork)

This repository is a modified fork of [hartrusion/RbmkSimulator](https://github.com/hartrusion/RbmkSimulator), created to provide headless dedicated server support and multiplayer UDP position relay for an external 3D control room front-end.

## Summary of Modifications
- Added `--headless` launch support in `RbmkSimulator` to run the simulation engine without a Swing GUI.
- Added `UdpPlayerRelay` on UDP port `26486` to relay player positions and orientations between connected clients.
- Added thread synchronization (`simLock`) and null-safe property filtering in `MainLoop` when loading `.ic` simulation states.

## License (GNU GPLv3)
In accordance with the **GNU General Public License v3.0** (`LICENSE`), the complete corresponding source code for this modified simulation server is made publicly available here under the same GPLv3 license. All original copyright notices and license terms from `hartrusion` are preserved verbatim.

### Architecture & Separate Works Notice
- **Simulation Server (`RbmkServer`):** Licensed under **GNU GPLv3** (see [`LICENSE`](./LICENSE)).
- **Unity 3D Front-End (Separate Application):** The Unity 3D control room client is an independent, proprietary application. It does not link against, embed, or derive from `RbmkSimulator` source code or Java libraries; it runs as a separate process and communicates strictly over standard TCP/UDP network sockets.
