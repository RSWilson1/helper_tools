# helper_tools

Command-line helpers for clinical bioinformatics work on the DNAnexus platform.

Four tools, all dependency-light: the two shell scripts need only bash, coreutils
and `find`; the two Python scripts need only the standard library and the `dx`
CLI on `PATH`. Nothing imports `dxpy`, so they work anywhere `dx` does.

| Tool | What it does |
|---|---|
| [`bfind`](#bfind) | Local file search with bioinformatics file classes and index-pairing checks |
| [`dxurl`](#dxurl) | DNAnexus object IDs → platform URLs, including markdown links for docs |
| [`dxf`](#dxf) | `dx find data` without the `--path`/`--name` boilerplate; resolves data↔index pairs |
| [`dxjob`](#dxjob) | Job triage: state, runtime, cost, failure reason, filtered logs |

## Install

```bash
git clone https://github.com/RSWilson1/helper_tools.git ~/claude/helper_tools
cd ~/claude/helper_tools
./install.sh --dry-run     # see what it would change
./install.sh               # add bin/ to PATH, install the ripgrep config
```

`install.sh` is idempotent and backs up anything it replaces. Add
`--fix-gitconfig` to collapse duplicate `[user] name` entries in `~/.gitconfig`.

---

## bfind

Wraps `find(1)`. Every run builds exactly one `find` command — `--dry-run`
prints it, so nothing is hidden.

```bash
bfind --bam --orphan-index /data/runs     # BAMs with no index next to them
bfind --fastq --paired /seq/incoming      # FASTQs whose R1/R2 mate is missing
bfind --vcf --sample NA12878,NA12891 ~/p  # VCFs for specific samples
bfind --bam --bigger-than 5G --sort -size -l
bfind --log --newer-than 1d -x 'grep -l ERROR {}'
bfind SampleSheet --sheet ~ --newer-than 30d
```

**File classes** (combine freely; multiple classes are OR'd):
`--bam` `--vcf` `--fastq` `--bed` `--ref` `--index` `--sheet` `--log` `--qc`
`--json` `--dx`, or `--class a,b`.

**Domain filters:**

- `--orphan-index` — data files with no matching index. Understands both the
  sidecar (`x.bam.bai`) and stem (`x.bai`) conventions, and accepts either
  `.tbi` or `.csi` for a bgzipped VCF.
- `--paired` — FASTQs whose mate is absent (`_R1`/`_R2` and `_1`/`_2`).
- `--empty` — zero-byte files, the usual signature of truncated output.
- `--sample ID[,ID…]` — match sample IDs anywhere in the filename.

**Size/age:** `--bigger-than 100M` `--smaller-than 2G` `--newer-than 7d`
`--older-than 30` (bare number = days; `h`/`m` suffixes also work).

**Output:** `-l/--long` `-c/--count` `-s/--sum` `--sort size|time|path`
(prefix `-` to reverse) `--head N` `-0/--print0` `-x/--exec 'cmd {}'`.

`.git`, `node_modules`, `.venv`, `.nextflow`, `.snakemake` and `work` are
pruned by default so pipeline scratch is not walked; `--all` disables that,
`-H/--hidden` includes dotfiles.

## dxurl

Successor to the older `dx-url`. The differences all came from watching the
old one fail:

- the class prefix is **case-insensitive** (`Job-xxxx` works) while the hash is
  left byte-exact;
- `project-`, `container-`, `applet-`, `workflow-`, `database-` and `app-` are
  handled, not just job/analysis/file/record;
- it accepts the composite `project-X:file-Y` form that
  `dx find data --brief` emits, and takes the project from it **instead of
  calling the API**;
- many IDs per run, from argv or stdin, with describes fanned out in parallel;
- the clipboard only fires for a single result on a TTY, not on every run.

```bash
dxurl job-J98Kp9Q4XJPJjJpGy5YPk9Y9
dxurl Project-J9k05G04Pyg0PbVkyk98K10J            # case-insensitive
dx find data --brief --name '*.vcf.gz' | dxurl --md   # doc-ready links
dxurl --md --project project-J9k0 job-J98K job-J93v  # no API calls needed
dxurl --reverse 'https://platform.dnanexus.com/panx/projects/ABC/monitor/job/XYZ'
```

Formats: default plain URL, `--md`, `--html`, `--tsv`, `--json`, `--label TXT`.
Behaviour: `-p/--project` `-n/--no-name` `-P/--parallel N` `-r/--reverse`
`-o/--open` `-c/--copy` `-C/--no-copy`.

> The job, analysis and file URL shapes are the ones in daily use. The
> project, applet, workflow, database and app shapes follow the same `/panx`
> scheme but are less battle-tested — check one before bulk-linking.

## dxf

Replaces two recurring patterns. This:

```bash
dx find data --path "$PROJECT:$DIR" --name '*_markdup.bam' --brief
```

becomes `dxf --bam -p "$PROJECT" -f "$DIR"`. And a hand-rolled `find_bai()`
loop — one `dx find data` call per BAM — becomes:

```bash
dxf --bam --pair                  # each BAM with its .bai, one extra query total
dxf --bam --pair --missing        # only BAMs with NO index
dxf --bam --pair --require-index  # non-zero exit if any index is missing
```

`--pair` fetches the index objects once and matches them client-side on
`(project, folder, name)`, so cost is two queries regardless of file count.

```bash
dxf '*.vcf.gz'                       # current project
dxf --bam -f /runs/run1 --long       # state, size, path
dxf --vcf --sample 26058S0022 --md   # markdown links, via dxurl
dxf --bam -f /runs --sum             # total bytes
```

Classes: `--bam` `--vcf` `--fastq` `--bed` `--ref` `--index` `--sheet` `--qc`
`--conf`. Scope: `-p/--project` `-f/--folder` `-A/--all-projects` `--state`.
Output: `-b/--brief` (default) `-l/--long` `-T/--tsv` `-J/--json` `--paths`
`--names` `--md` `-c/--count` `-s/--sum`, with `--sort name|size|time`,
`-R/--reverse` and `--limit N`.

Exits 1 when nothing matches, so `--missing` composes:
`if dxf --bam --pair --missing; then echo "orphans found"; fi`

## dxjob

`dx describe job-xxxx` returns ~80 fields when the question is nearly always
*did it work, how long, what did it cost, and if it broke, why*.

```bash
dxjob job-J98Kp9Q4XJPJjJpGy5YPk9Y9   # done  2m23s  $0.0111  eggd_…  workbook-…
dxjob -l job-J98K                    # detail, incl. failureReason/Message
dxjob --recent 10                    # last 10 jobs
dxjob --failed                       # recent failures, with reasons inline
dxjob --tree job-J98K                # job plus subjobs
dxjob --outputs job-J98K             # output JSON
dxjob --url job-J98K                 # platform link, via dxurl
```

`--log` replaces the recurring `dx watch --no-follow JOB | grep -E '…'`:

```bash
dxjob --log job-J98K --grep 'Total variants (in input|included|excluded)'
dxjob --log job-J98K --tail 40
dxjob --watch job-J98K               # follow live
```

States are colourised on a TTY. A named job in state `failed` makes `dxjob`
exit non-zero, so it composes in scripts.

## Configuration

`config/ripgreprc` gives `rg` bioinformatics-aware defaults: custom types
(`rg -tvcf`, `-tfastq`, `-tdx`, `-tsmk`) and glob excludes for BAM/CRAM/index/
gzipped-FASTQ so searches stop walking binary data. Uncompressed `.vcf` and
`.bed` are deliberately *not* excluded — they are text and worth grepping.

`config/shell.sh` puts `bin/` on `PATH`, sets `RIPGREP_CONFIG_PATH`, and adds
a few dx shortcuts (`dxrec`, `dxfail`, `dxcat`, `dxwhere`).
