# Cli

- [Commands and groups](#commands-and-groups)
- [Executing commands](#executing-commands)
- [Help output](#help-output)

## Commands and groups

`src/XeWeCore/Cli/Cli.h`: the types a command is made of, and how groups are registered.

### Types

```cpp
using command_function_t = std::function<void(xewe::span<const std::string> args)>;

struct Command {
    std::string        name;
    std::string        description;
    std::string        sample_usage;
    std::size_t        arg_count;
    command_function_t function;
};

struct CommandGroup {
    std::string          id;
    std::string          name;
    std::vector<Command> commands;
};
```

**No member has a default initializer**, so aggregate initialization must supply all five fields
of `Command`, in order:

```cpp
{"set", "Set level 0-255", "$led set 128", 1,
 [](xewe::span<const std::string> args) { analogWrite(8, atoi(args[0].c_str())); }}
```

| Field | |
|---|---|
| `name` | typed after the group; matched **case-insensitively** |
| `description` | shown in the `$help` table |
| `sample_usage` | printed when the argument count is wrong; may be empty |
| `arg_count` | exact number of arguments required, not a minimum |
| `function` | the handler; must not be empty |

`CommandGroup::id` holds the normalized (trimmed, lowercased) id.

### Commands a module gets from the core

`xewe::Module` registers `status` and `reset` in every module's group, plus `enable` and `disable`
when the module can be disabled. A module with a [settings table](../Settings/README.md) also gets
`set`, `get` and `schema` at `begin()`, except names the module registered itself. They are
ordinary commands; see [`Module/README.md`](../Module/README.md#generic-cli-commands).

### Constructor

```cpp
explicit Cli(SerialPort& serial);
```

The `Cli` stores a **reference** to the port, which must outlive it. Both are normally globals:

```cpp
xewe::SerialPort serial;
xewe::Cli        xewe_cli(serial);
```

**Do not write `cli(` or `cli (`.** The ESP32 Arduino core defines `cli` as a function-like macro,
so `xewe::Cli cli(serial);` expands to something that does not compile. Brace initialization
(`cli{serial}`) and member access are fine: `XeWeOs` names its member `cli` (`os.cli.execute(...)`)
and initialises it with braces. A standalone object in a sketch is best named `xewe_cli`.

### loop

```cpp
void loop();
```

Non-blocking: calls `serial.loop()` and, when a complete line is available, executes it. Call it
every sketch iteration.

A handler blocks this loop while it runs: a command that calls `delay()` stops everything else.

### add_group

```cpp
CommandGroup& add_group(std::string_view id, std::string_view name);
```

Creates the group, or returns the existing one. The `id` is trimmed and lowercased; it is what the
user types after `$`. The `name` is the display title in help output.

**Re-adding an existing id keeps its commands and only updates the display name.** The returned
reference is a live handle into the internal map.

### add_command

```cpp
bool add_command(std::string_view group_id, Command command);
```

Appends a command to a group. Returns `false` and adds nothing when:

* the group does not exist,
* `command.name` is empty or contains whitespace (the tokenizer splits on it, so it could never be
  typed), or
* `command.function` is empty.

Through [`Module::register_command`](../Module/README.md) a rejected command is also reported, for
example `! $<id> command '<name>' contains whitespace: not registered`. The other reasons are
`is empty` and `has no function`.

**Duplicate command names are not rejected.** Commands with the same name act as an overload set
on `arg_count`: both [`execute`](#executing-commands) overloads pick the command whose name **and**
argument count match. When no count matches, the parsed path reports the mismatch against the
first command of that name. Of two commands with the same name and count, the first one registered
wins; the second is unreachable.

**Module ids are checked before their group is created.** `Os::register_module` refuses a module
whose id is empty, contains whitespace, equals `help` (`$help` is intercepted), is longer than 15
characters (the NVS namespace limit), or is already registered. The last check also compares
case-insensitively against existing groups. It prints, for example,
`! Module id '<id>' is already registered: module not registered`. A refused module gets no group
and no commands, so a duplicate never merges into the first module's group. The checks are
`Cli::name_error(name, is_module_id)`.

`add_group` itself does not validate. Called directly, it merges into an existing id, and a group
id of `help` or one with whitespace is registered but reachable only through the direct `execute`
overload.

Commands are stored in registration order, which is the order `$help` lists them in.

### remove_group

```cpp
bool remove_group(std::string_view id);
```

Erases a group and all of its commands. Returns `true` if something was erased.

### get_group and get_groups

```cpp
const CommandGroup*                        get_group (std::string_view id) const;
const std::map<std::string, CommandGroup>& get_groups()                    const;
```

`get_group` returns `nullptr` for an unknown id. `get_groups` exposes the map keyed by lowercase
id, so iterating it is alphabetical by id.

## Executing commands

`src/XeWeCore/Cli/Cli.h`: the two `execute` overloads, the tokenizer, and every error the parsed path
prints.

### execute (parsed)

```cpp
void execute(std::string_view input_line) const;
```

Parses a full line of the form `$<group> <command> [args...]` and dispatches it. Returns nothing:
**errors are printed to the serial port**, not returned.

`loop()` calls it for each typed line. Call it to run a command from code, such as a button
handler, a schedule or a web request:

```cpp
xewe_cli.execute("$led set 10");
```

#### Dispatch order

| Input | Result |
|---|---|
| empty or whitespace only | silently ignored |
| no leading `$` | `Error: commands must start with '$'; type $help` |
| `$` alone | `Error: Missing command group; usage: $<group> <command> [args...]` |
| unterminated quote | `Error: Unterminated quote in command.` (see [Tokenizer](#tokenizer)) |
| `$help` | [`print_all_commands()`](#help-output) |
| `$help <group>` | [`print_help(group)`](#help-output) |
| `$help a b` | `Error: Argument count mismatch for '$help'; usage: $help <group>` |
| unknown group | `Error: Unknown command group '<g>'` |
| group with no commands | `Error: Command group '<g>' has no CLI commands` |
| `$<group>` with no command | that group's help |
| `$<group> help` | that group's help |
| `$<group> ""` (empty command token) | `Error: Missing command in command group '<g>'; usage: $<g> <command> [args...]` |
| unknown command | `Error: Unknown command '<c>' in command group '<g>'` |
| wrong argument count | `Error: Argument count mismatch for '$<g> <c>'; expected <N>, got <M>`, then `Usage: <sample_usage>` when one is set |

Group ids and command names are both matched **case-insensitively**, so `$LED Set 128` works.

The check order matters: an unknown group is reported before an empty one, and the argument count
is checked before the handler runs, so a handler never sees the wrong number of arguments.

### execute (direct)

```cpp
bool execute(std::string_view             group_id,
             std::string_view             command_name,
             xewe::span<const std::string> args) const;
```

Skips parsing and returns whether a command ran. It prints nothing, not even on failure.

```cpp
std::vector<std::string> args{"128"};
if (!xewe_cli.execute("led", "set", args)) { /* no such command */ }
```

A command matches when its `function` is non-empty, its name matches case-insensitively, **and
`args.size() == command.arg_count`**. Commands that share a name and differ in arity act as an
overload set, as in the parsed path. The parsed path falls back to the first command of that name
only to report an argument-count mismatch.

Returns `false` when the group is unknown or nothing matched.

### Handler arguments

A handler receives `xewe::span<const std::string>` over a vector owned by `execute`.

**The span does not outlive the call.** Copy anything you intend to keep.

```cpp
{"name", "Set the name", "$dev name \"Kitchen\"", 1,
 [this](xewe::span<const std::string> args) { stored_name = args[0]; }}   // copy, not a view
```

`execute` copies the input line before tokenizing. A handler may therefore modify the caller's
buffer, call `execute` again, or add and remove commands and groups, its own included. The handler
runs from a copy of its `std::function`, so removing its own group does not destroy it mid-call.

### Tokenizer

The `$` is stripped, then the rest is split on whitespace:

* A token starting with `"` runs to the closing `"` and may contain spaces.
* Inside quotes, `\` escapes the next character, including `"`, so `"abc\"` is an unterminated
  quote. Outside quotes `\` is literal: `a\ b` is the two tokens `a\` and `b`.
* A closing quote ends the token: `"a"b` is the two tokens `a` and `b`.
* **Quoting only applies when `"` is the first character of a token:** `ab"cd"` is one literal
  token, quotes included.
* An unterminated quote prints `Error: Unterminated quote in command.` and **aborts the whole
  line**; nothing runs.
* `$ led set 10`, with a space after the `$`, is accepted.

```
$dev name "Kitchen Lights"       -> args: ["Kitchen Lights"]
$dev name "say \"hi\""           -> args: ["say \"hi\""]
```

## Help output

`src/XeWeCore/Cli/Cli.h`: the generated `$help` tables.

### print_all_commands

```cpp
void print_all_commands() const;
```

Prints one table per group, in **alphabetical order by group id**. This is what `$help` runs.

**Groups with no commands are skipped.** A group registered but never filled does not appear in
help.

### print_help

```cpp
void print_help(std::string_view group_id) const;
```

Prints one group's table. The id is trimmed and matched case-insensitively; an **empty id runs
`print_all_commands()`**. `$help <group>`, `$<group>` and `$<group> help` run it. An unknown id
prints `Error: Unknown command group '<g>'`; a group without commands prints
`Error: Command group '<g>' has no CLI commands`.

### What a table looks like

The table is rendered with
[`SerialPort::print_table`](../Serial/README.md#print_table-and-render_table)
with that function's defaults: 30-character column cap, `|` edges, `+` corners. Its title is
`<group name> Commands [<group id>]`, and the columns are fixed:

```
+-------------------------------------------------+
|               LED Commands [led]                |
+---------+------+-----------------+--------------+
| Command | Args | Description     | Sample Usage |
+---------+------+-----------------+--------------+
| set     | 1    | Set level 0-255 | $led set 128 |
+---------+------+-----------------+--------------+
```

Commands are listed in registration order. A command with an empty `name` or an empty `function`
is skipped, which is the same condition that makes it unreachable from
[`execute`](#executing-commands).

Long descriptions wrap inside their column instead of widening the table.
