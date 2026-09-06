# Build recipe correction — 2026-09-06

Daniel Campos Ramos requested a verified updated compiler release and package. OpenAI Codex's coordinating partner found and corrected this existing recipe defect while preparing that release. No compiler algorithm or CMake source changed. This receipt is configure evidence, not a compiler build or promotion.

## Finding and actual build logic

CMakeLists.txt:761-780 reads ZIG_RELEASE_SAFE to choose ReleaseSafe; otherwise its non-Debug/non-MinSizeRel path chooses ReleaseFast. Stripping is appended unless CMAKE_BUILD_TYPE equals RelWithDebInfo. The documented CMAKE_BUILD_TYPE=ReleaseSafe alone therefore gives the opposite of the intended self-hosted compiler posture on a fresh cache. Existing build-p005 and build-safe caches already declare CMAKE_BUILD_TYPE=RelWithDebInfo and ZIG_RELEASE_SAFE=ON; their generated stage3 command contains -Doptimize=ReleaseSafe. This finding does not imply the existing promoted binary is ReleaseFast.

## Executed discriminating configuration

Both fresh configurations exited 0. CMake ran its small system-compiler detection probes; no zig1/zig2/stage3 build was fired and no compiler was promoted.

~~~sh
cmake -S . -B build-recipe-negative-2026-09-06 -G Ninja -DCMAKE_BUILD_TYPE=ReleaseSafe -DZIG_STATIC_LLVM=OFF -DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions -DZIG_VERSION=0.16.0+cgm.recipe-check
cmake -S . -B build-recipe-positive-2026-09-06 -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DZIG_RELEASE_SAFE=ON -DZIG_STATIC_LLVM=OFF -DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions -DZIG_VERSION=0.16.0+cgm.recipe-check
~~~

The one generated stage3 COMMAND in each build.ninja was inspected (1 of 1 each):

~~~text
build-recipe-negative-2026-09-06
COMMAND = cd /K3D/GitHub/cgm-zig && /K3D/GitHub/cgm-zig/build-recipe-negative-2026-09-06/zig2 build --prefix /K3D/GitHub/cgm-zig/build-recipe-negative-2026-09-06/stage3 --zig-lib-dir /K3D/GitHub/cgm-zig/lib -Dversion-string=0.16.0+cgm.recipe-check -Dtarget=native -Dcpu=native -Denable-llvm -Dconfig_h=/K3D/GitHub/cgm-zig/build-recipe-negative-2026-09-06/config.h -Dno-langref -Ddebug-extensions -Doptimize=ReleaseFast -Dstrip

build-recipe-positive-2026-09-06
COMMAND = cd /K3D/GitHub/cgm-zig && /K3D/GitHub/cgm-zig/build-recipe-positive-2026-09-06/zig2 build --prefix /K3D/GitHub/cgm-zig/build-recipe-positive-2026-09-06/stage3 --zig-lib-dir /K3D/GitHub/cgm-zig/lib -Dversion-string=0.16.0+cgm.recipe-check -Dtarget=native -Dcpu=native -Denable-llvm -Dconfig_h=/K3D/GitHub/cgm-zig/build-recipe-positive-2026-09-06/config.h -Dno-langref -Ddebug-extensions -Doptimize=ReleaseSafe
~~~

Negative: ReleaseSafe=false, unstripped=false, debug-extensions=true. Positive: ReleaseSafe=true, unstripped=true, debug-extensions=true. The negative reproduces the old recipe and visibly fails the intended safety/no-strip invariant; the positive corrects it. Both use the same untouched production CMake source, SHA256 6b1860dce31d09071110cdd731a985d760dc0f090744323f578a19e37b119edb. No source sabotage required restoration; both generated directories remain retained. No dynamic compiler safety or benchmark claim is made.

## Correction

The build guide and fork skill now specify the two correct switches, warn against confusing their roles, and direct a candidate into a fresh repo-local build directory. The skill resolves PROMOTED/zig as station authority rather than treating the build-safe directory name as identity. No model/account/permission settings were touched.

| File | Before | After |
|---|---|---|
| docs/crown/BUILDING.md | 8d1b0cd501b594cfc2b09e3cb46b731585afa55f1ee2979cd44dfc77b2385c8e | 039aabe57127751380ce41dc7ce8eab12d260c84226efe490538e74fd0ec1060 |
| .claude/skills/cgm-zig/SKILL.md | a836855a8ffad9f08565b44e99078952e9f00f01082b7dc88990c4924c12fb86 | 93e7d02de2735f996819c057063c40321b4bb11ca709a0711fdbbe26289d8f05 |

Skill validation command:
~~~sh
python3 /home/daniel/.codex/skills/.system/skill-creator/scripts/quick_validate.py .claude/skills/cgm-zig
~~~
Result: exit 0, Skill is valid. This checks skill structure, not build correctness; the generated commands above are the behavioral evidence.

## Separate main-reference preparation

Fresh remote main and patch branch remained 63effbe93c276735c56c6d8ab1cb3f2149365c19. The clean local main worktree had no process cwd inside it at 2026-09-06T22:18:11.603Z. Its local-only6377899732bbccaa3cdab0c686169c903a880de3 was patch-equivalent to e0bcdab2 already online. Root fetched main, preserved backup/main-before-sync-2026-09-06 at that old tip, then rebased local main onto origin/main. Git skipped the equivalent commit and returned success. Post-read: main=origin/main=63effbe93c276735c56c6d8ab1cb3f2149365c19, backup retains6377899732bbccaa3cdab0c686169c903a880de3, local main worktree clean. No force reset or push occurred. The source-author branch and promoted binary were untouched by this reference repair.

Release build, verification, packaging, publication and synchronization of the NEW work remain pending; the user has authorized them after verification without another permission question.

