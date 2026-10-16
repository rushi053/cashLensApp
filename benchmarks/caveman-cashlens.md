# Caveman on CashLens: token and cost check

Measured 2026-10-16 on this repo (`cashLensApp`), Caveman CLI `4.0.1` / engine `bin-v4.0.1`, skill file `~/.agents/skills/caveman/SKILL.md` (sha256 `415d43518f2b1a9498c15a445d4657117b129ee5e81b19454ce348439cc6672b`, 1,158 tokens).

## Verdict

Not worth leaving on for day-to-day work in this repo.

The response skill does make long explanations shorter. Across four normal coding tasks it cut the final answer by about 37%, and it cut one explanation by 59%. The rest of each run is file reads, searches, and tool calls. Add those in and the four tasks together saved **0.5%** of counted tokens. Two of the four got more expensive, because the terse agent searched more or issued an extra command.

The local compressor is a different tool, and it is sharp only on repetitive text. A synthetic test log fell from 29,100 tokens to 151 (99.5%), and the failure line survived. The same compressor left Swift source and the real 5,000-expense export unchanged (0%). An agent that answers that export with a short Python script never loads the file, so there is nothing for the proxy to save.

Do not expect the published "33% fewer input tokens" figure on ordinary CashLens edits. That number is from a Claude Code benchmark on noisy fixtures, not from this app.

## How the tokens were counted

Eleven fresh agents, one arm each, same model family as this session (Cursor Grok 4.7, `inherit`). No Caveman Cloud, no Auto mode, no sign-in. Telemetry was forced off before the first `caveman` command (`DO_NOT_TRACK=1`, `CAVEMAN_TELEMETRY=0`, then `caveman telemetry off`). Nothing was merged and no product file was edited. The agents were told not to write files. The worktree stayed clean apart from this report.

Cursor did not return provider usage. Counts are tiktoken `o200k_base` on the saved transcripts:

- **Input:** the task prompt plus tool results.
- **Output:** assistant text plus tool-call arguments.
- **Total** in the table is input + output. Thinking tokens are real and often larger than the answer. They are listed separately and are not in the headline total.
- Some `read_file` results were missing from the transcript, so input is a lower bound. The same gap applies to every arm.

Dollar figures are not a Cursor invoice. They convert the counted tokens at Claude Sonnet 5.5 public list price on 2026-10-07: **$2 / million input tokens** and **$10 / million output tokens**. Thinking, when included, is priced as output.

The skill text pasted into the caveman prompts was a shortened restatement of the installed `SKILL.md`, about 100 to 320 extra prompt tokens depending on the task. The real file is 1,158 tokens. This run therefore **understates** the skill's input cost. Loading the full file on every turn would shrink the savings below, and on the short tasks it would erase them.

`/caveman` is not a switch in this cloud agent. The skill installer wrote files under `~/.agents/skills/` and did not change the repo. The caveman arms followed those rules only because the prompt included them.

## Agent runs

| Task | Arm | Input | Output | Total | Saved vs baseline | Final answer | Est. cost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Explain import/export | baseline | 16,076 | 2,708 | 18,784 |  | 1,759 | $0.059 |
| Explain import/export | skill | 13,687 | 1,715 | 15,402 | 18.0% | 719 | $0.045 |
| Find one import/export bug | baseline | 19,819 | 2,584 | 22,403 |  | 616 | $0.065 |
| Find one import/export bug | skill | 23,884 | 1,996 | 25,880 | −15.5% | 218 | $0.068 |
| Write an `ExpenseFilter` unit test | baseline | 4,869 | 2,189 | 7,058 |  | 1,472 | $0.032 |
| Write an `ExpenseFilter` unit test | skill | 3,918 | 1,874 | 5,792 | 17.9% | 1,340 | $0.027 |
| Facts from the 5,000-row export, plus "can we run tests?" | baseline | 1,302 | 1,766 | 3,068 |  | 388 | $0.020 |
| Facts from the 5,000-row export, plus "can we run tests?" | skill | 1,739 | 2,263 | 4,002 | −30.4% | 399 | $0.026 |
| Summarize a 1,501-test log | baseline (raw log) | 5,614 | 406 | 6,020 |  | 208 | $0.015 |
| Summarize a 1,501-test log | CLI compress only | 443 | 242 | 685 | 88.6% | 150 | $0.003 |
| Summarize a 1,501-test log | CLI compress + skill | 520 | 224 | 744 | 87.6% | 133 | $0.003 |

The four skill-vs-baseline coding tasks sum to 51,313 baseline tokens and 51,076 caveman tokens (**0.5%** saved, about $0.177 vs $0.165 at the list price above). Final answers alone fell from 4,235 to 2,676 tokens (37%). That is the part a person reads. It is also the small part of the bill.

Thinking, priced as output, does not change the story. Explain and the unit test still save. The bug hunt and the fact check still cost more. The log task stays near 88% saved.

One run per arm. A second run could move the bug-hunt and fact-check rows, because those deltas came from extra searches and an extra shell command, not from a longer answer.

## Quality

Rubric fixed before the answers came back. Tests could not be compiled: `swift`, `swiftc`, and `xcodebuild` are not on this machine.

| Task | Baseline | Caveman | What changed |
| --- | --- | --- | --- |
| Explain import/export | 8/8 required facts | 8/8 | No required fact dropped. The baseline answer also caught three extra real defects: `JSONSerialization` rejecting nil optionals boxed as `Any`, CSV amounts using `%.2f` under the device locale, and deleted-category `UserDefaults` writes happening before the Core Data save. The short answer did not. |
| Find a data-loss bug | 2/2 | 1/2 | Baseline: CSV import splits on newlines before it honors quotes, so a note with a line break aborts the whole file. The patch parses records with quotes in mind. Caveman: content dedupe plus date-only CSV dates can drop a second same-day expense. That failure is real. The patch deletes content dedupe instead of keeping the time or widening the key. |
| `ExpenseFilter` tests | 5/5 by inspection | 5/5 by inspection | Both cover custom-category id, date range overriding `timeFrame`, exclusive end, and newest-first order, with `@Test` and `#expect`. Not compiled. |
| Export facts | 11/11 | 11/11 | Same JSON, including sum `6613488.8`, max expense `867A0DCB-49B9-4B42-8C90-AA16D93B0585`, and 386 subscription-linked expenses. Both correctly said the Swift toolchain is missing. The printed needle amount `5494.2034926597362` is the same float as the file's `5494.203492659736`. |
| Test log | failure found | failure found | Raw log, compressed log, and compressed log plus skill all reported 1,501 tests, 1 failure, `testCSVSubscriptionLink`, `CashLens/Models/Expense.swift:359`, id `2BEAE4C6-9A75-4157-93D8-0BD761EBFD9B`. |

The log is a fixture, not a live `xcodebuild`. It is 1,500 passing lines plus one failure that matches a real CSV gap (`subscriptionId` forced to nil). It exists so the compressor had a CashLens-shaped test log to chew on.

## What the CLI actually compressed

`caveman tools compress` and `caveman tools toon encode`, engine token counts (`o200k_base`) except TOON, which the CLI did not meter. TOON tokens are tiktoken on the output file. No model call.

| Payload | Tokens before | Tokens after | Saved |
| --- | ---: | ---: | ---: |
| `ExpenseViewModel+ImportExport.swift` | 4,083 | 4,083 | 0% |
| `CashLens_StressTest_5000.json` (1.8 MB, compress) | 669,264 | 669,264 | 0% |
| Same JSON, `shrink` as terminal text | 669,264 | 665,465 | 0.6% |
| Same JSON, minified only (not Caveman) | 669,264 | 465,513 | 30.4% |
| Same JSON, `caveman tools toon encode` | 669,264 | 335,425 | 49.9% |
| Synthetic repetitive log, `--type log` | 278,056 | 296 | 99.9% |
| Synthetic test log, `--type terminal` | 29,100 | 151 | 99.5% |

The engine is behaving safely on the export: every row is data, so it refuses to drop rows. The 98% JSON cuts in Caveman's own write-up are for fixtures that hide one needle in a pile of noise. Minify and TOON beat `compress` on this file because they keep every value and only remove punctuation and repeated keys. The fact-check agents never needed either. Two or three Python commands answered from the file, and the model saw about 1,000 to 1,300 tokens of tool output, not 669,264.

Log compression is lossy (`lossless_to_model: false`). On the test log the unique failure was kept verbatim. On the repetitive log the error line was kept, and the elided ranges were a bit loose. Original bytes for a real compression go into the local recovery store.

Full agent wrap was not run. `caveman claude` (and the other named agents) needs that agent's binary and login, and the first successful wrap persists host config. This session has no Claude, Codex, or Gemini login, and the instructions were to stay signed out. `caveman tools compress` / `shrink` / `toon` are the local CLI path that does not need an account.

## Setup friction

- Node on this machine is v22.14.0, which meets the CLI's 22.13+ bar.
- `npm install -g @caveman-ai/cli@latest` was one package and finished in about a second. The bare `caveman` npm name is a different library. The package that matters is `@caveman-ai/cli`.
- `caveman tools compress` is a pass-through until `caveman setup --install`. That step downloaded six signed binaries, about 177 MB, into `~/.caveman/bin/` (proxy, engine, mcp, memory, browse, shrink). Checksums were verified. The installer then printed `next: caveman claude`.
- `npx skills add JuliusBrussee/caveman -g` cloned the GitHub repo, installed **22** skills into `~/.agents/skills/`, and then reported `Failed to install 22` because PromptScript has no global skill path. The Cursor copy path did not modify this repo. Easy to misread as a failed install.
- There is no `/caveman` command in this cloud agent after that install. You paste the skill or rely on a client that actually loads `~/.agents/skills`.

## Outside the repo, and network

- Telemetry is on by default. The client posts usage metadata (not prompts or code, per their docs) to `https://xvfgtprkhzlvegvmeefq.supabase.co/functions/v1/cli-telemetry`. With `DO_NOT_TRACK=1` set before install, `caveman telemetry status` stayed `off`, `anonymous_id` was `none`, and `~/.caveman/cloud.json` records `"enabled": false`. A later `compress` showed **no** TCP connections. This run did not observe a telemetry send. A default install without that env var would.
- No `caveman login`, no Caveman Cloud, no paid signup.
- Compression that actually shrinks text stores the original in `~/.caveman/ccr.db` (mode 600). After the log fixtures that file was 2.6 MB. It is outside the repo, on purpose, so a later `retrieve` can restore bytes. It is still a second copy of whatever you compress.
- Skill install writes under `~/.agents/`, not the git worktree.
- Binary download is the other network use (release artifacts, checksum-verified). npm and the skill clone talked to the npm registry and GitHub.

## Bottom line

Use the skill when you want a shorter explanation and you are willing to lose the extra caveats. Do not use it to save money on coding turns in Cursor: the reply is the cheap part, and a terser agent can spend the savings on more tool calls. Use `caveman tools compress --type log` or `shrink` when a command is about to dump thousands of near-identical lines. Leave the proxy off for Swift and for this app's JSON exports. If you install the CLI at all, set `DO_NOT_TRACK=1` first.
