# Troubleshooting a node fleet

A runbook for the questions that come up when nodes "restart on their own".
Every command runs on the host, from this directory. Node containers are named
`nodeN-node` and `nodeN-postgres`; `node{1..10}` below assumes a ten-node fleet
started with `./start_nodes.sh` — adjust the range to your fleet.

Terminal tip: if your terminal wraps pasted lines, commands that span lines get
mangled. Every command here fits on one line, or uses a `F=...` variable first.

---

## 1. Was it a restart or a rebuild?

Two very different things look like "the node restarted":

| What happened | Container ID | `RestartCount` | `FinishedAt` | Env file mtime | Image ID |
|---|---|---|---|---|---|
| **Process crashed**, Docker restarted it in place | same | goes up | set | unchanged | unchanged |
| **Script rebuilt/recreated it** (`node.sh up`, `start_nodes.sh`, `update.sh`) | new | reset to 0 | zero time | rewritten | usually new |

Check every node in one go:

```bash
F='{{.Name}} r={{.RestartCount}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} created={{.Created}} started={{.State.StartedAt}} died={{.State.FinishedAt}}'
for c in node{1..10}-node; do docker inspect -f "$F" $c; done
```

- `r=0` and `died=0001-01-01…` → the container has never exited. If `created`
  is recent, it was **recreated by a script** — go to section 2.
- `r>0` with a real `died` time → the **process crashed** — go to section 3.
- Several nodes with the same `died` second → one event hit them all (a
  published pubsub message, a DB outage, the host).

Exit codes when a crash is reported: `137` = SIGKILL (OOM killer or `docker
kill`), `143` = SIGTERM (`docker stop`, daemon shutdown), `2` = Go panic,
`1` = application error or `entrypoint.sh` bailing out.

---

## 2. Who or what recreated the containers?

`node.sh up` rewrites `.env.nodeN` before it calls compose, so the env mtimes
are a timeline of the run. `update.sh` and `start_nodes.sh` step through the
nodes about 6.5 s apart.

```bash
ls -l --time-style=full-iso .env.node*
docker images 'rubix-node' --format '{{.Tag}} {{.ID}} {{.CreatedAt}}'
```

Then find the caller. Replace the window with the env-file timestamp:

```bash
last -F | head -20
sudo journalctl --since "2026-09-08 06:20" --until "2026-09-08 06:35" --no-pager | grep -iE 'sshd|session|sudo'
crontab -l; sudo crontab -l; ls /etc/cron.d; systemctl list-timers --all --no-pager | head
FMT='{{.Time}} {{.Action}} {{.Actor.Attributes.name}}'
docker events --since 2026-09-08T06:20:00Z --until 2026-09-08T06:35:00Z --format "$FMT"
```

Bash writes `~/.bash_history` only when a shell **exits**. If the command is
missing from the file, run this in every terminal that is still open on the
host (including screen/tmux windows):

```bash
HISTTIMEFORMAT='%F %T  ' history | grep -E 'update|start_nodes|node.sh|kill_nodes' | tail
```

Things that recreate node containers without anyone meaning to:

- `./update.sh --all --branch <ref>` **always** re-clones and rebuilds, even if
  the branch has no new commits. Use `--check` first.
- `EXTERNAL_IP=` left blank in `.env.nodeN`: every `up` re-queries
  api.ipify.org and injects the answer into the container. A different answer
  (or a failed lookup) changes the container definition and compose recreates
  it. Pin it: `./node.sh up N --external-ip <ip>`.
- A CI/deploy hook that SSHes in and runs a script. It leaves no `last` entry
  and no history; only `journalctl` shows the login.

---

## 3. Reading a crash

Docker keeps logs across in-place restarts (same container), and
`entrypoint.sh` prints `Starting Rubix node...` on every boot. The lines just
before the **second** banner are the old process's last words:

```bash
docker logs node8-node 2>&1 | grep -c 'Starting Rubix node'          # boots since creation
N=$(docker logs node8-node 2>&1 | grep -n 'Starting Rubix node' | sed -n 2p | cut -d: -f1)
docker logs -t node8-node 2>&1 | sed -n "$((N-60)),${N}p"
```

Count panics across the fleet (adjust `--since`):

```bash
for N in $(seq 1 10); do echo "node$N: panics=$(docker logs --since 2026-09-09T00:00:00Z node${N}-node 2>&1 | grep -c '^panic:')"; done
```

What you will see:

- `panic: …` followed by a `goroutine … [running]:` trace → a bug in
  `rubixgoplatform`. The first frame under `core.` is the file and line to fix.
  Copy the whole trace into the issue.
- An `[ERROR]` line and then the banner → the application exited on purpose;
  the message says why (DB unreachable, config, network mismatch).
- Log stops mid-line, no error → killed from outside. Check memory:

```bash
sudo dmesg -T | grep -iE 'out of memory|killed process|oom' | tail
free -h
docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' | sort
```

A node that crashes while it is quorum or receiver for a transaction drops that
transaction. Nodes that crash at the same second usually all handled the same
pubsub event.

Logs are lost when a container is **recreated** (section 1), so capture the
trace before running any `up`/`update` command.

---

## 4. Which branch / binary is a node running?

Ask Docker, not the env file. Every image built from this repo carries labels
and a `/app/BUILD_INFO` file written at build time, so the answer describes the
bytes actually running, not what someone last typed into `.env.nodeN`.

```bash
./node.sh status 3                      # "build" section: image, branch, commit, commit date
docker exec node3-node cat /app/BUILD_INFO
```

Whole fleet, one line per node:

```bash
for c in $(docker ps -a --format '{{.Names}}' | grep -- '-node$' | sort -V); do echo "$c  $(docker inspect -f '{{index .Config.Labels "org.rubixchain.source"}} {{index .Config.Labels "org.rubixchain.branch"}}{{index .Config.Labels "org.rubixchain.version"}}' $c)  $(docker exec $c sh -c 'cut -d= -f2 /app/BUILD_INFO 2>/dev/null | sed -n 3p')"; done
```

Output is `name  source branch-or-version  commit`, e.g.
`node3-node  branch development  9f1c2e…`. Release images print
`release v1.0.5` with no commit.

Images built **before** these labels existed show empty labels and no
`BUILD_INFO`. For those, the image tag is the only Docker-side record (slashes
in the branch name become dashes), and the compiled-in Go VCS stamp gives the
commit:

```bash
docker inspect -f '{{.Config.Image}}' node3-node
docker exec node3-node grep -a -o -m1 'vcs.revision=[0-9a-f]*' /app/rubixgoplatform
```

Rebuild once (`./node.sh up 3 --rebuild`, or `./update.sh --all --rebuild`) and
the labels appear.

Is the running commit the branch head?

```bash
git ls-remote https://github.com/rubixchain/rubixgoplatform <branch>
```

A different hash means someone pushed after the last `--rebuild`.

The env file still matters for one thing: it is what the **next** `up` will
build. `grep -HE '^(BUILD_BRANCH|RUBIX_VERSION)=' .env.node*` shows that. If it
disagrees with the labels, the next `up` will switch the node.

---

## 5. Switching branch or version

Every command here rebuilds the image and **recreates the container** — one
restart per node, data kept. Do it in a quiet window; in-flight transactions on
that node are lost.

```bash
./node.sh up 3 --branch <ref>          # one node → branch/tag/SHA (saved in .env.node3)
./node.sh up 3 --rebuild               # same branch, pick up new commits
./node.sh up 3 --version v1.0.5        # one node → release binary (clears BUILD_BRANCH)

./update.sh --all --check              # preview only, changes nothing
./update.sh --all --branch <ref>       # whole fleet → branch (asks Proceed? [y/N])
./update.sh --all --rebuild            # whole fleet, new commits on current branch
./update.sh --all --release            # whole fleet → latest release
```

A plain `./node.sh up` or `./start_nodes.sh` **does not** pick up new commits:
Docker serves the cached clone. Only `--rebuild` (or a new `--branch`) does.

Afterwards, confirm with section 4.

---

## 6. Quick reference

| Symptom | First command | Section |
|---|---|---|
| "Nodes restarted" | inspect loop (`RestartCount`, `FinishedAt`) | 1 |
| Restart count is 0 but container is new | `ls -l --time-style=full-iso .env.node*` | 2 |
| Restart count > 0 | log tail before 2nd banner | 3 |
| Several nodes died the same second | compare their log tails | 3 |
| Which code is running? | `grep vcs.revision` | 4 |
| Move to a branch / new commits | `./update.sh --all --check` then `--branch`/`--rebuild` | 5 |
