# Working with other developers on GitHub

Written for someone who has used Git alone but not *with a team*. Covers the
mental model, then the exact steps in **VS Code** and in the **GitHub website**.

---

# Part 1 — The mental model

## Why branches exist

`main` is the version everyone trusts. It should always work.

If two people edit `main` directly, they overwrite each other and nobody can
tell which change broke what. So instead:

```
main      ●───●───●───────────────●───●      always working
               \                 /
feature         ●───●───●───────●            your work, isolated
```

You **branch off** `main`, do your work in isolation, then **merge back** once
someone has reviewed it.

## The four words you need

| Word | What it means |
|---|---|
| **branch** | A separate line of work. Cheap — make one per task |
| **commit** | A saved checkpoint with a message explaining *why* |
| **push** | Send your commits to GitHub so others can see them |
| **pull request (PR)** | "Please review my branch and merge it into main" |

## The loop, every single time

```
1. pull main          get everyone else's latest work
2. create a branch    feature/add-customer-segment
3. do the work        edit, save, test
4. commit             small, with a real message
5. push               your branch goes to GitHub
6. open a PR          ask for review
7. review + merge     someone approves, it goes into main
8. delete the branch  it's done
```

**Rule one: never commit directly to `main`.** Even alone. It builds the habit,
and it means `main` always has a reviewed history.

---

# Part 2 — In VS Code

VS Code has Git built in. The **Source Control** icon in the left sidebar
(three connected dots) is where everything happens.

## One-time setup

```bash
git clone https://github.com/kundudeblina24-svg/dbt-project.git
cd dbt-project
code .
```

Or in VS Code: `Ctrl+Shift+P` → **Git: Clone** → paste the URL.

## Start a new piece of work

**Bottom-left corner** of VS Code shows the current branch (e.g. `main`).

1. Click it
2. Choose **Create new branch from…** → `main`
3. Name it `feature/add-customer-segment`

Or in the terminal:

```bash
git checkout main
git pull                                   # ALWAYS pull before branching
git checkout -b feature/add-customer-segment
```

> **Branch naming.** Use a prefix so the list stays readable:
> `feature/…` new work · `fix/…` a bug · `chore/…` tidying.
> Never `test`, `test2`, `deblina-branch`.

## Make your changes and commit

1. Edit files, save
2. **Source Control** panel — changed files appear under *Changes*
3. Hover a file → **+** to stage it (or **+** on *Changes* to stage everything)
4. Type a commit message in the box at the top
5. **Ctrl+Enter** to commit

**Commit messages: say WHY, not what.** The diff already shows what changed.

```
BAD:   "updated model"
BAD:   "fixes"
GOOD:  "Switch fct_orders to merge strategy

        The 7-day lookback re-reads rows that already exist, so append
        was duplicating them on every run."
```

## Push and open a PR

1. **Source Control** → **⋯** menu → **Push**
   (first time it says *Publish Branch*)
2. VS Code shows a notification offering to **Create Pull Request** — click it
3. Or go to the repo on github.com; a yellow banner appears with
   **Compare & pull request**

## Keep your branch up to date

If someone merges to `main` while you're working:

```bash
git checkout main
git pull
git checkout feature/add-customer-segment
git merge main            # bring their changes into your branch
```

Do this **often**. Merging one day of other people's changes is easy; merging
three weeks of them is not.

---

# Part 3 — On the GitHub website

Useful for small edits, reviewing, and when you're not at your machine.

## Create a branch

1. Repo home → the branch dropdown (says **main**)
2. Type a new name → **Create branch: feature/… from main**

## Edit a file

1. Navigate to the file → **pencil** icon
2. Edit
3. Scroll down → **Commit changes**
4. Choose **Create a new branch for this commit and start a pull request**

## Open a pull request

1. **Pull requests** tab → **New pull request**
2. **base: `main`** ← **compare: `your-branch`**
3. **Create pull request**
4. Title + description. Say what changed and why. Link an issue with `#12`
5. Add a **Reviewer** on the right

## Review someone else's PR

This is the part people skip, and it's most of collaboration.

1. **Pull requests** → open theirs
2. **Files changed** tab
3. Hover any line → **+** → leave a comment on that exact line
4. **Review changes** (top right) → choose one:
   - **Comment** — thoughts, no verdict
   - **Approve** — good to merge
   - **Request changes** — needs work before merging

**What to actually look for in a dbt PR:**

- Does the model have a `unique` test on its key? That's the grain assertion
- Is there a `description`? Undocumented models become nobody's models
- Does it use `ref()` everywhere, never a hardcoded table name?
- Is business logic sitting in staging where it belongs in a mart?
- Would this change break anything downstream? (`dbt ls --select model+`)

## Merge

Once approved: **Merge pull request** → **Confirm merge** → **Delete branch**.

Three merge buttons exist:

| Option | Result | Use when |
|---|---|---|
| **Create a merge commit** | Keeps every commit + a merge commit | Default, safe |
| **Squash and merge** | All your commits become **one** | **Best for most work** — keeps `main` history clean |
| **Rebase and merge** | Replays commits, no merge commit | Teams that want a linear history |

Most teams use **Squash and merge**.

---

# Part 4 — Conflicts

A conflict happens when you and someone else changed **the same lines**. Git
can't decide, so it asks you.

```
<<<<<<< HEAD
    order_status IN ('placed', 'shipped')
=======
    order_status IN ('placed', 'shipped', 'delivered')
>>>>>>> main
```

- Above `=======` is **yours**
- Below is **theirs**

VS Code shows buttons above the block: **Accept Current** / **Accept Incoming**
/ **Accept Both**. Pick, or hand-edit to the correct result, then delete the
`<<<<<<<`, `=======`, `>>>>>>>` markers.

```bash
git add the_file.sql
git commit
```

**Conflicts are normal.** They are not a sign anyone did anything wrong. The way
to have fewer is to pull often and keep branches short-lived.

---

# Part 5 — Protecting `main`

Once more than one person is on the repo:

**Settings → Branches → Add branch protection rule**, pattern `main`:

- ☑ Require a pull request before merging
- ☑ Require approvals (1 is enough for a small team)
- ☑ Require status checks to pass (once CI exists)

That makes "never commit to main" enforced rather than remembered.

---

# Part 6 — What this means for a dbt project

## What gets committed

```
COMMITTED                         NOT COMMITTED (.gitignore)
---------                         --------------------------
models/**.sql, **.yml             .env            <- the token
macros/, snapshots/, tests/       target/         <- compiled output
dbt_project.yml                   logs/
profiles.yml  (env_var only!)     dbt_packages/
.env.example
```

`profiles.yml` **is** committed — because it contains no secrets, only
`env_var()` references. The token lives in `.env`, which is gitignored.

> **The pattern to describe in an interview:** *the shape of the config is
> versioned, the values are not.*

## A realistic dbt feature branch

```bash
git checkout main && git pull
git checkout -b feature/add-customer-segment

# 1. write the model
#    models/marts/dim_customers.sql

# 2. write its tests IN THE SAME COMMIT
#    models/marts/_marts.yml

# 3. run only what changed and what depends on it
source env.sh
dbt build --select dim_customers+ --target dev

git add models/
git commit -m "Add customer_segment to dim_customers

Segments on completed order count so the definition lives in one place
instead of being redefined in each dashboard."
git push -u origin feature/add-customer-segment
```

Then open the PR.

## Slim CI — what a team actually runs on a PR

```bash
dbt build --select state:modified+ --defer --state ./prod-artifacts
```

- `state:modified+` — only changed models **and everything downstream**
- `--defer` — unchanged parents resolve to the **production** tables instead of
  being rebuilt

Three models build instead of two hundred and fifty.

---

# The rules that matter

1. **Never commit to `main`.** Always a branch, always a PR.
2. **Pull before you branch.** Every time.
3. **Small branches.** One task. A branch open for three weeks is pain you are
   scheduling for later.
4. **Commit messages say why.** The diff already shows what.
5. **Never commit secrets.** If you do, rotate the credential — deleting the
   file does not remove it from history.
6. **Tests go in the same commit as the model.** Not "later".
7. **Review other people's PRs.** It is how you learn the codebase.

---

# Commands worth knowing

```bash
git status                          # what's changed - use constantly
git checkout main && git pull       # get latest
git checkout -b feature/thing       # new branch
git add .                           # stage everything
git commit -m "message"             # save a checkpoint
git push -u origin feature/thing    # first push of a new branch
git push                            # subsequent pushes
git log --oneline -10               # recent history
git diff                            # unstaged changes
git diff --cached                   # staged changes
git branch                          # list local branches
git checkout main                   # switch branch
git merge main                      # bring main into your branch
git stash                           # park changes temporarily
git stash pop                       # get them back
```

**If you break something and want out:**

```bash
git checkout -- file.sql     # discard changes to one file
git reset --soft HEAD~1      # undo last commit, KEEP the changes
git reset --hard HEAD        # discard everything uncommitted (careful!)
```
