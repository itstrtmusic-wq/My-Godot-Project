# Cinderline

A single-player survival shooter set in a salvage valley. Recover parts to power Relay 04, build cover in the clearing, and keep the uplink alive through three drone waves.

## Play

Open [project.godot](project.godot) in Godot 4.6.3 and press **F5**, or import with `godot --headless --editor --import` and then run `godot --path .` from this directory. Choose **New deployment**. The project uses Godot's Compatibility renderer and needs no external assets, services, or add-ons.

Pick up marked salvage with **E**. You need **9 Alloy** and **5 Fiber** to start the defense. Fabricate ammunition and trauma patches with **Tab**. Build cover before installing the parts, and use **E** at the relay during the defense to repair it for **2 Alloy**. The game saves before the first wave so you can retry the defense with your materials, position, and structures intact.

| Input | Action |
| --- | --- |
| WASD and mouse | Move and look |
| Shift, Ctrl, Space | Sprint, crouch, jump |
| Left mouse, right mouse, R | Fire, aim, reload |
| E | Salvage or interact |
| Tab | Fabricator |
| F, V | Eat a ration, apply a trauma patch |
| B | Enter or exit build mode |
| 1, 2, 3 | Select wall, gate, canopy |
| Left mouse, R, X in build mode | Place, rotate, dismantle |
| Esc | Pause or return to gameplay |

Use Settings to adjust sensitivity, field of view, volume, or camera motion. Set motion to zero to turn off camera bob, roll, and recoil movement.

## Checkpoints

Cinderline autosaves during preparation and after the relay goes online. The pause menu can save whenever an assault is inactive. During an assault, retrying returns to the checkpoint made before the relay was powered. Continue also tries the previous valid save if the primary file is damaged.

The solo checkpoint and settings live under Godot's `user://` application data directory. Use **Project → Open User Data Folder** in the editor to locate the files.

## Verify and export

Run `./tests/check.sh` on Linux with Godot 4.6.3 on your PATH. Set `GODOT_BIN` to use a specific binary. The script imports the project, boots the title scene, and exercises the survival loop with an isolated save profile.

For standalone executables, install the official export templates matching the editor version and select an export preset. For example, from a clean checkout on Linux:

```sh
mkdir -p build/linux build/windows
godot --headless --editor --import
godot --headless --export-release "Linux" build/linux/Cinderline.x86_64
godot --headless --export-release "Windows Desktop" build/windows/Cinderline.exe
```

Keep the Windows executable beside its PCK. When distributing a standalone build, include `LICENSE` and generate the engine notices with `godot --headless --script res://tests/engine_notices.gd -- build/ENGINE-NOTICES.txt`.

Use `--export-pack "Linux" build/Cinderline.pck` to make a resource pack that can be started with `godot --main-pack build/Cinderline.pck`.

The original movement test scene remains available at [demo/movement_lab.tscn](demo/movement_lab.tscn). Project source is licensed under [Apache-2.0](LICENSE).
