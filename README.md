<h2 align="center">🦀 tsrs for Ruby</h2>

<h4 align="center">A drop-in replacement for the TypeScript 7 compiler and language server, written in Rust.</h4>

<div align="center">Ruby bindings for <a href="https://github.com/oxc-project/tsrs">tsrs</a>, the Rust port of the TypeScript 7 type checker.</div><br/>

<p align="center">
  <a href="https://rubygems.org/gems/tsrs"><img alt="Gem Version" src="https://img.shields.io/gem/v/tsrs"></a>
  <a href="https://github.com/oxc-project/tsrs"><img alt="Documentation" src="https://img.shields.io/badge/oxc--project%2Ftsrs-documentation-green"></a>
  <a href="https://github.com/marcoroth/tsrs-ruby/blob/main/LICENSE.txt"><img alt="License" src="https://img.shields.io/github/license/marcoroth/tsrs-ruby"></a>
  <a href="https://github.com/marcoroth/tsrs-ruby/issues"><img alt="Issues" src="https://img.shields.io/github/issues/marcoroth/tsrs-ruby"></a>
</p>

<br/>

### What is tsrs for Ruby?

Ruby bindings for [tsrs](https://github.com/oxc-project/tsrs), a drop-in replacement for the TypeScript 7 compiler and language server, written in Rust. Type check, compile and transpile TypeScript from Ruby, without the need for a JavaScript runtime.

Everything here is tsrs doing the work. For what the options mean and what it can do, the [TypeScript documentation](https://www.typescriptlang.org/tsconfig/) is the reference.

### Installation

```bash
bundle add tsrs
```

Anywhere a precompiled gem is not published, the gem builds from source and needs the [Rust toolchain](https://rustup.rs). tsrs needs a recent Rust, 1.99.1 at the moment. `rust/rust-toolchain.toml` pins it, so rustup installs it for the build.

### Versioning

The gem carries the version of tsrs it packages. Gem v0.18.0 bundles tsrs v0.18.0. `Tsrs.tsrs_version` reports what a given build was compiled against, and `Tsrs.typescript_version` reports the TypeScript version that tsrs release is a port of.

So the version tracks tsrs, not the Ruby API here. If the gem needs releasing again for the same tsrs version, that release adds a fourth digit, as in v0.18.0.1.

### Usage

#### Type checking

```ruby
require "tsrs"

result = Tsrs.check(cwd: "app/javascript")
# => #<Tsrs::CheckResult status=2 errors=1 diagnostics=1>

result.success?
# => false

puts result
# app/javascript/src/index.ts:1:7 - error TS2322: Type 'string' is not assignable to type 'number'.

result.errors.first.code
# => 2322
```

Without arguments, tsc finds the `tsconfig.json` in `cwd`. You can also point it at a project, or at files:

```ruby
Tsrs.check(project: "app/javascript/tsconfig.json")
Tsrs.check("app/javascript/index.ts", strict: true)
```

`Tsrs.check` never writes anything, as with `tsc --noEmit`. `validate!` raises `Tsrs::TypeError` if there were errors, so a rake task can fail on them:

```ruby
task :typecheck do
  Tsrs.check(cwd: "app/javascript").validate!
end
```

#### Checking again and again

`Tsrs.check` runs tsc's command line, which is built to check once and exit, so a check's memory stays with the process. For anything long-lived, like a web server, a file watcher or a test suite that checks often, use a session instead:

```ruby
session = Tsrs::Session.new(cwd: "app/javascript")

session.check.validate!                      # tsconfig.json in cwd
session.check("admin/tsconfig.json").errors  # or any other project

session.close
```

`Tsrs::Session.open(cwd: ...) { |session| ... }` closes the session when the block returns. A session is tsrs's API server, the same one behind tsrs's Node API. Each check builds the program in a snapshot and releases it afterwards, so memory levels off instead of growing by about 38 MB a check. Checks report the same diagnostics as `Tsrs.check`. They pick up what changed on disk since the last check, including the `tsconfig.json`, and can run from several threads at once.

The project's `tsconfig.json` decides the compiler options: a session check takes none of its own. It never writes anything, and raises `Tsrs::CheckError` when there is no project to load.

#### Compiling

`Tsrs.compile` runs tsc and writes its outputs, the way `tsc` does:

```ruby
Tsrs.compile(project: "tsconfig.json", declaration: true)
```

`Tsrs.tsc` takes command-line arguments exactly as `tsc` would:

```ruby
Tsrs.tsc("--listFilesOnly", cwd: "app/javascript").output
```

#### Transpiling one file

`Tsrs.transpile` turns one TypeScript source into JavaScript without type checking it, like TypeScript's `transpileModule`. It doesn't look at the file system:

```ruby
Tsrs.transpile("export const answer: number = 42;", target: "es2020").code
# => "export const answer = 42;\n"

result = Tsrs.transpile(source, file_name: "app.tsx", jsx: "react-jsx", source_map: true)
result.code
result.map
```

`Tsrs.transpile_declaration` emits the `.d.ts` for a source written for `isolatedDeclarations`:

```ruby
Tsrs.transpile_declaration("export function greet(name: string): string { return name; }").code
# => "export declare function greet(name: string): string;\n"
```

A source that doesn't parse raises `Tsrs::SyntaxError`, which carries the diagnostics.

#### Compiler options

Compiler options are tsc's, written in snake case or as tsc spells them. They are passed to tsc as command-line flags, so tsc reads them the way it always does:

| Ruby | tsc |
| --- | --- |
| `strict: true` | `--strict` |
| `no_emit: false` | `--noEmit false` |
| `target: "es2022"` | `--target es2022` |
| `lib: ["es2022", "dom"]` | `--lib es2022,dom` |
| `"esModuleInterop" => true` | `--esModuleInterop` |

Options that only make sense in a terminal, like `watch`, `build`, `init` and `help`, raise `Tsrs::OptionError`. So does a hash, which tsc's command line can't express. Put options like `paths` in a `tsconfig.json`.

#### Diagnostics

Each `Tsrs::Diagnostic` has a `code`, a `category` (`:error`, `:warning`, `:suggestion` or `:message`), a `message`, a `file`, and a 1-based `line` and `column`. `start` and `finish` are offsets in UTF-16 code units, the unit TypeScript counts in. `message_chain` and `related_information` hold the elaborations tsc attaches, and `to_s` prints a diagnostic the way tsc does.

#### Threads and memory

Every call releases the GVL, so other Ruby threads keep running and several checks can run at once. The work runs on a few long-lived native threads with large stacks, since type checking recurses deeply.

Transpiling gives back all the memory it used, and so does checking with a `Tsrs::Session`. `Tsrs.check`, `Tsrs.compile` and `Tsrs.tsc` don't: tsrs runs them like `tsc`, a process that checks once and exits, so much of what they allocate stays with the process. That's fine for a rake task or CI. In a long-lived process, check with a session instead.

### Development

The gem is a C extension over a Rust crate. `rust/` builds a static library and generates the C header with [cbindgen](https://github.com/mozilla/cbindgen), `ext/tsrs/` wraps it, and `lib/` is the Ruby API over that.

tsrs doesn't publish its crates, so `rust/Cargo.toml` takes them from the release tag on GitHub. `rust/.cargo/config.toml` stamps the TypeScript version the way tsrs's own release builds do. The upstream workflow keeps the tag, that version, and the Rust toolchain in step with each tsrs release.

```bash
bin/setup
bundle exec rake
```

`sig/` is generated from the `#:` annotations next to the code. Regenerate it with `rake rbs` after changing a signature, and CI checks that it matches.

### Acknowledgements

[tsrs](https://github.com/oxc-project/tsrs) is maintained at [oxc-project/tsrs](https://github.com/oxc-project/tsrs), and is a port of [TypeScript](https://github.com/microsoft/TypeScript). This gem only calls into it. Thank you for building these tools!

### Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marcoroth/tsrs-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/marcoroth/tsrs-ruby/blob/main/CODE_OF_CONDUCT.md).

Issues with type checking or emit belong [upstream](https://github.com/oxc-project/tsrs/issues), with a minimal reproduction, since this gem does none of that itself. Issues with the Ruby API, the build, or the bindings belong here.

### License

The Ruby, C, and Rust code in this gem is available under the terms of the [MIT License](https://opensource.org/licenses/MIT).

It builds against [tsrs](https://github.com/oxc-project/tsrs), which is Apache-2.0 licensed and a derivative of TypeScript. Its native extension embeds TypeScript's `lib.*.d.ts` files. tsrs's license and NOTICE travel with the gem in [`licenses/`](licenses).
