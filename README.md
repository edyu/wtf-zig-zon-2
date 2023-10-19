# Zig Package Manager 2 - WTF is Build.Zig.Zon and Build.Zig (0.11.0 Update)

The ~~power~~ hack and complexity of **Package Manager** in Zig 0.11.0

---

Ed Yu ([@edyu](https://github.com/edyu) on Github and
[@edyu](https://twitter.com/edyu) on Twitter)
Oct.18.2023

---

![Zig Logo](https://ziglang.org/zig-logo-dark.svg)

## Introduction

[**Zig**](https://ziglang.org) is a modern system programming language and although it claims to a be a **better C**, many people who initially didn't need system programming were attracted to it due to the simplicity of its syntax compared to alternatives such as **C++** or **Rust**.

However, due to the power of the language, some of the syntaxes are not obvious for those first coming into the language. I was actually one such person.

Several months ago, when I first tried out the new **Zig** package manager, it was before [0.11.0](https://github.com/ziglang/zig/releases/tag/0.11.0) was officially released. Not only was the language unstable, but also the package manager itself was subject to a lot of stability issues especially with TLS. I had to hack together a system that worked for my need, and I documented my journey in [WTF is Zon](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e).

Since then I've had discussion of the **Zig** _package manager_ with [Andrew](https://github.com/andrewrk) and various others through the [Zig Discord](https://discord.com/servers/zig-programming-language-605571803288698900), [Ziggit](https://ziggit.dev), and even a [Github issue](https://github.com/ziglang/zig/issues/16172).

Now that **Zig** has released [0.11.0](https://github.com/ziglang/zig/releases/tag/0.11.0) in August 2023, and many of the problems were resolved so I want to revisit my hack to see whether I can do a better _hack_.

A special shoutout to my friend [InKryption](https://github.com/inkryption), who was tremendously helpful in my understanding of the _package manager_. I wouldn't be able to come up with this better hack without his help.

## Disclaimer

As I mentioned in my [previous article](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e), I changed my typical subtitle of _power and complexity_ to _hack and complexity_ because not only was [0.11.0](https://github.com/ziglang/zig/releases/tag/0.11.0) (hence the package manager) not released yet but also I had do a pretty ugly [hack](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e#provide-a-package) to make it work.

I just want to reiterate my stance on **Zig** and the _package manager_. I'm not writing this to discourage you from using it but to set the right expectation and hopefully help you in case you encounter similar issues.

**Zig** along with its package manager is being constantly improved and I'm looking forward to the [0.12.0](https://github.com/ziglang/zig/milestone/23) release.

Today, I'll introduce a better hack than what I had to do in June, 2023 and hopefully I can retire my hack after the [0.12.0](https://github.com/ziglang/zig/milestone/23) release.

I'll most likely write a follow-up article after **Zig** [0.12.0](https://github.com/ziglang/zig/milestone/23) is released hopefully by the end of the year.

I will not reiterate concepts introduced in [Part 1](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e), so please read that first if you find this article confusing.

## Package (Manager) vs Library

One of my previous misunderstandings of the package manager was that I was using a **Zig** package as a library.

Let's reuse the example of C -> B -> A in that _program C_ that depended on the _package B_, which in turn depended on _package A_.

The way I was building the _program C_ and _packages B and A_ was that I was basically _copying_ over everything _package A_ produced to _package B_ and then _copied_ over both what _package B_ produced and _package A_ produced to _program C_ as part of the build process.

That was not the correct way to use a package manager because one of the benefits of the package manager is that you only need to concern yourself with the packages you depended on directly without needing to care what that other packages needed they depended on.

In the example of C -> B -> A, _program C_ should only know/care about _package B_ and not needing to care at all that _package B_ needed _package A_ internally because the package manager should have taken care of the transitive dependencies.

In other words, package manager should have good enough encapsulation for packages in that the users should not care about packages not directly required by the main program.

As an example, despite many of the dependency problems, _npm_ does a good job (probably too good a job) of encapsulation.

It's so good that sometimes when you add 1 package, you might be surprised when _npm_ automatically pulls down hundreds of packages because it would recursively download all depenencies.

However, such clean encapsulation is not always possible when we are building native programs in **Zig** especially when shared libraries are involved.

## Artifact and Module

The main problem I had to deal with was that the **Zig** package manager resolved around the idea of an _artifact_ which requires a _Compile_ step that involves with either compilation and/or linking.

This conceptualization doesn't work well with when we have to deal with a package composed of existing binary library such as a shared library that doesn't require any additional compilation or linking.

Although the **Zig** package manager also has the concept of a _module_ but it is mainly used so that you program can import **Zig** package.

A module is equivalent to a **Zig** library (source code) exposed by the package manager. A _module_ is not useful when you don't your binary library is not written in **Zig**.

For building your program, you need the _artifact_ produced by the dependencies in order to access the specific items produced by such dependencies.

If your package is written in **Zig**, then you can access the **Zig** library in such package as a _module_ and you can access either the shared libarary, static library, or the executable as _artifacts_.

## The Problem

I'll reintroduce the problem mentioned in [Part 1](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e).

The scenario is common in a project that uses a package written in a different language from your main project:

A: You often would need the shared or static library from the package written in another language compiled for your environment (such as **Linux**).
B: You would also need to write a wrapper for such library in your native language.
C: You then would write your program calling the functions provided by the wrapper _B_.

Our concrete example has 3 packages _A_, _B_, and _C_. Our program _my-wtf-project_ is in _package C_, which needs to use [DuckDb](https://duckdb.org) for its database needs.

The project C will use the **Zig** layer provided by _package B_, which in turn will need the actual [DuckDb](https://duckdb.org) implementation provided by _package A_.

For our `my-wtf-project`, our main program will call the **Zig** library provided by [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb). The [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb) is just a **Zig** wrapper of [libduckdb](https://github.com/beachglasslabs/libduckdb) that provides the dynamic library of [release 0.9.1](https://github.com/duckdb/duckdb/releases/tag/v0.9.1) of [DuckDb](https://duckdb.org).

To use the C -> B -> A example in the earlier section, _program C_ is our project `my-wtf-project`, _package B_ is [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb), and _project A_ is [libduckdb](https://github.com/beachglasslabs/libduckdb).

Note that _package B_ used to be called `duckdb.zig` but it has since been renamed to [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb).

## The Hack

There are two hacks I had to do for the `build.zig` of _package A_([libduckdb](https://github.com/beachglasslabs/libduckdb)),
_package B_([zig-duckdb](https://github.com/beachglasslabs/zig-duckdb)), and _program C_(_my-wtf-project_):

1. In the `build.zig` of [libduckdb](https://github.com/beachglasslabs/libduckdb), I had to create an _artifact_ even if the `libduckdb.so` is a shared library that doesn't need additional compilation/linking by creating a new static library that is linked to `libduckdb.so` just so I can use the _artifact_ in
   [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb).

2. I had to use `lib.installHeader` to install both the `duckdb.h` and the `libduckdb.so` in all the `build.zig` to copy over these 2 files to `zig-out/include` and `zig-out/lib` respectively.

## A: [libduckdb](https://github.com/beachglasslabs/libduckdb)

The [duckdb](https://github.com/duckdb/duckdb) was written in **c++** and the `libduckdb-linux-amd64` release from [duckdb](https://github.com/duckdb/duckdb) only provided 3 files: `duckdb.h`, `duckdb.hpp`, and `libduckdb.so`.

I unzipped the package and placed `duckdb.h` under the `include` directory and `libduckdb.so` under the `lib` directory.

## build.zig.zon of A: [libduckdb](https://github.com/beachglasslabs/libduckdb)

Because [libduckdb](https://github.com/beachglasslabs/libduckdb) has no dependencies, the _zon_ file is extremely simple.

It just lists the name and the version. I've intentionally been using the actual version number of the underlying [DuckDb](https://duckdb.org).

```zig
// build.zig.zon
// there are no dependencies
.{
    // note that we don't have to call this libduckdb
    .name = "duckdb",
    .version = "0.9.1",
}
```

## build.zig of A: [libduckdb](https://github.com/beachglasslabs/libduckdb)

This is the first big change from [Part 1](https://github.com/beachglasslabs/libduckdb/blob/57bb5689984c598494b40b91d79cdbe8ed102279/build.zig). We are not building anymore fake artifact. We are only introducing some _modules_ so that any package depending on this package can reference these items using the various _module_ names. This is still a **hack** because technically these items are _artifacts_ not _modules_ but at least we don't have to compile a shared library that doesn't need to be compiled.

```zig
pub fn build(b: *std.Build) !void {
    _ = b.addModule("libduckdb.lib", .{ .source_file = .{ .path = b.pathFromRoot("lib") } });
    _ = b.addModule("libduckdb.include", .{ .source_file = .{ .path = b.pathFromRoot("include") } });
    _ = b.addModule("duckdb.h", .{ .source_file = .{ .path = b.pathFromRoot("include/duckdb.h") } });
    _ = b.addModule("libduckdb.so", .{ .source_file = .{ .path = b.pathFromRoot("lib/libduckdb.so") } });
}
```

This will make more sense in the next sections.

## B: [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb)

The [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb) is still a minimal **Zig** wrapper to [DuckDb](https://duckdb.org). It suits my needs for now and the only changes added since last time are the ability to query for `boolean` and `optional` values.

The big change is that we no longer need to install `libduckdb.so` or `duckdb.h` from [libduckdb](https://github.com/beachglasslabs/libduckdb).

## build.zig.zon of B: [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb)

We do have a dependency now as we need to refer to a release of A: [libduckdb](https://github.com/beachglasslabs/libduckdb).

```zig
// build.zig.zon
// Now we depend on a release of A: libduckdb
.{
    .name = "duck",
    .version = "0.0.5",

    .dependencies = .{
        // this is the name you want to use in the build.zig to reference this dependency
        // note that we didn't have to call this libduckdb or even duckdb
        .duckdb = .{
            .url = "https://github.com/beachglasslabs/libduckdb/archive/refs/tags/v0.9.1.3.tar.gz",
            .hash = "1220e182337ada061ebf86df2a73bda40e605561554f9dfebd6d1cd486a86c964e09",
        },
    },
}
```

## build.zig of B: [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb)

Note that we no longer _install_ `libduckdb.so` or `duckdb.h` as part of the build process we previous had to do in [Part 1](https://github.com/beachglasslabs/zig-duckdb/blob/8aab6c6029cb8d9e0492f3135f892f10cbd1e3bf/build.zig).

We do have to call `addModule` multiple times to expose not only the library `libduck.a` (the _artifact_ of this package) itself but also _re-export_ the modules provided by [libduckdb](https://github.com/beachglasslabs/libduckdb).

Note how we now call `duck_dep.builder.pathFromRoot(duck_dep.module("libduckdb.include").source_file.path` to access the `include` directory and `duck_dep.builder.pathFromRoot(duck_dep.module("libduckdb.lib").source_file.path)` to access the `lib` directory.

You can think of this as equivalent of reaching inside of [libduckdb](https://github.com/beachglasslabs/libduckdb) to access these items and therefore we don't have to copy these items into our output directory anymore as we previously had to do with `lib.installLibraryHeaders(duck_dep.artifact("duckdb"))`.

```zig
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const duck_dep = b.dependency("duckdb", .{});

    // this is our main wrapper file
    _ = b.addModule("duck", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    // (re-)add modules from libduckdb
    _ = b.addModule("libduckdb.include", .{
        .source_file = .{ .path = duck_dep.builder.pathFromRoot(
            duck_dep.module("libduckdb.include").source_file.path,
        ) },
    });

    _ = b.addModule("libduckdb.lib", .{
        .source_file = .{ .path = duck_dep.builder.pathFromRoot(
            duck_dep.module("libduckdb.lib").source_file.path,
        ) },
    });

    _ = b.addModule("duckdb.h", .{
        .source_file = .{ .path = duck_dep.builder.pathFromRoot(
            duck_dep.module("duckdb.h").source_file.path,
        ) },
    });

    _ = b.addModule("libduckdb.so", .{
        .source_file = .{ .path = duck_dep.builder.pathFromRoot(
            duck_dep.module("libduckdb.so").source_file.path,
        ) },
    });

    const lib = b.addStaticLibrary(.{
        .name = "duck",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.addLibraryPath(.{ .path = duck_dep.builder.pathFromRoot(
        duck_dep.module("libduckdb.lib").source_file.path,
    ) });
    lib.addIncludePath(.{ .path = duck_dep.builder.pathFromRoot(
        duck_dep.module("libduckdb.include").source_file.path,
    ) });
    lib.linkSystemLibraryName("duckdb");

    b.installArtifact(lib);

}
```

Note that if you really want to install `libduckdb.so` for example, you can do so with the following call:

```zig
_ = b.installLibFile(duck_dep.builder.pathFromRoot(
    duck_dep.module("libduckdb.so").source_file.path,
    ), "libduckdb.so");
```

If you look into the project, you will see that I introduced a new file called `test.zig` that was meant to test the new `boolean` and `optional` values.

In order to run the test, I've added a new _test_ step in build.zig:

```zig
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.step.dependOn(b.getInstallStep());
    unit_tests.linkLibC();
    // note how I use modules to access these directories
    unit_tests.addLibraryPath(.{ .path = duck_dep.builder.pathFromRoot(
        duck_dep.module("libduckdb.lib").source_file.path,
    ) });
    unit_tests.addIncludePath(.{ .path = duck_dep.builder.pathFromRoot(
        duck_dep.module("libduckdb.include").source_file.path,
    ) });
    unit_tests.linkSystemLibraryName("duckdb");

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.setEnvironmentVariable("LD_LIBRARY_PATH", duck_dep.builder.pathFromRoot(
        duck_dep.module("libduckdb.lib").source_file.path,
    ));

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
```

Once again, you can see that's why I've exposed the `lib` and `include` directories of [libduckdb](https://github.com/beachglasslabs/libduckdb) via _module_.
I can now call `addIncludePath` and `addLibraryPath` by referencing their modules.

Note the call to `setEnvironmentVariable` because `-L` is only useful for _linking_ not for running the test/program. Hence you need to point to `libduckdb.so` using `LD_LIBRARY_PATH` and once again by accessing the location of the shared library inside the [libduckdb](https://github.com/beachglasslabs/libduckdb) package.

## C: my-wtf-project

Now to create the executable for our project, we need to link to the packages A [libduckdb](https://github.com/beachglasslabs/libduckdb) and B [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb).

## build.zig.zon of C: my-wtf-project

Our only dependency is the release of B: [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb).

```zig
// build.zig.zon
// Now we depend on a release of B: zig-duckdb
.{
    // this is the name of our own project
    .name = "my-wtf-project",
    // this is the version of our own project
    .version = "0.0.2",

    .dependencies = .{
        // we depend on the duck package described in B
        .duck = .{
            .url = "https://github.com/beachglasslabs/zig-duckdb/archive/refs/tags/v0.0.5.tar.gz",
            .hash = "1220fe38df4d196b7aeca68ee6de3f7b36f1424196466038000f7485113cf704f478",
        },
    },
}
```

## build.zig of C: my-wtf-project

This is somewhat similar to the `build.zig` of B ([zig-duckdb](https://github.com/beachglasslabs/zig-duckdb)).

Note once again that we do not need to call `installLibraryHeaders` to install the `libduckdb.so` and `duckdb.h` anymore.

I've also added `setEnvironmentVariable` to set `LD_LIBRARY_PATH` for running the test program.

```zig
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-wtf-project",
        .root_source_file = .{ .path = "testzon.zig" },
        .target = target,
        .optimize = optimize,
    });

    const duck = b.dependency("duck", .{
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("duck", duck.module("duck"));
    exe.linkLibrary(duck.artifact("duck"));

    exe.addIncludePath(.{ .path = duck.builder.pathFromRoot(
        duck.module("libduckdb.include").source_file.path,
    ) });
    exe.addLibraryPath(.{ .path = duck.builder.pathFromRoot(
        duck.module("libduckdb.lib").source_file.path,
    ) });
    //  You'll get segmentation fault if you don't link with libC
    exe.linkLibC();
    exe.linkSystemLibraryName("duckdb");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    // you must set the LD_LIBRARY_PATH to find libduckdb.so
    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", duck.builder.pathFromRoot(
        duck.module("libduckdb.lib").source_file.path,
    ));

    const run_step = b.step("run", "Run the test");
    run_step.dependOn(&run_cmd.step);
}
```

## Running the executable

You can now just call `zig build run` to run the test program because we already set `LD_LIBRARY_PATH` using `setEnvironmentVariable` in our `build.zig`.

```fish
 I  ~/w/z/wtf-zig-zon-2 6m 10.7s ❱ zig build run
info: duckdb: opened in-memory db

info: duckdb: db connected

debug: duckdb: query sql select * from pragma_version();

Database version is v0.9.1


STOPPED!

Leaks detected: false
 I  ~/w/z/wtf-zig-zon-2 4.1s ❱
```

## Bonus: Package Cache

When I mentioned reaching inside the package, what happens behind the scene is that the package is in `~/.cache/zig` so all these magic with _module_ is really specifying the path to the particular packages under `~/.cache/zig`.

You can see more clearly what's going on if you add `--verbose` to your `zig build` or `zig build` commands.

```fish
 I  ~/w/z/wtf-zig-zon-2 4.1s ❱ zig build run --verbose
/snap/zig/8241/zig build-lib /home/ed/.cache/zig/p/1220fe38df4d196b7aeca68ee6de3f7b36f1424196466038000f7485113cf704f478/src/main.zig -lduckdb --cache-dir /home/ed/ws/zig/wtf-zig-zon-2/zig-cache --global-cache-dir /home/ed/.cache/zig --name duck -static -target native-native -mcpu znver3-mwaitx-pku+shstk-wbnoinvd -I /home/ed/.cache/zig/p/1220e182337ada061ebf86df2a73bda40e605561554f9dfebd6d1cd486a86c964e09/include -L /home/ed/.cache/zig/p/1220e182337ada061ebf86df2a73bda40e605561554f9dfebd6d1cd486a86c964e09/lib --listen=-
/snap/zig/8241/zig build-exe /home/ed/ws/zig/wtf-zig-zon-2/testzon.zig /home/ed/ws/zig/wtf-zig-zon-2/zig-cache/o/b893f00994b9c79eab2c150de991b233/libduck.a -lduckdb -lduckdb -lc --cache-dir /home/ed/ws/zig/wtf-zig-zon-2/zig-cache --global-cache-dir /home/ed/.cache/zig --name my-wtf-project --mod duck::/home/ed/.cache/zig/p/1220fe38df4d196b7aeca68ee6de3f7b36f1424196466038000f7485113cf704f478/src/main.zig --deps duck -I /home/ed/.cache/zig/p/1220e182337ada061ebf86df2a73bda40e605561554f9dfebd6d1cd486a86c964e09/include -L /home/ed/.cache/zig/p/1220e182337ada061ebf86df2a73bda40e605561554f9dfebd6d1cd486a86c964e09/lib --listen=-
LD_LIBRARY_PATH=/home/ed/.cache/zig/p/1220e182337ada061ebf86df2a73bda40e605561554f9dfebd6d1cd486a86c964e09/lib /home/ed/ws/zig/wtf-zig-zon-2/zig-out/bin/my-wtf-project
info: duckdb: opened in-memory db

info: duckdb: db connected

debug: duckdb: query sql select * from pragma_version();

Database version is v0.9.1


STOPPED!

Leaks detected: false
 I  ~/w/z/wtf-zig-zon-2 ❱
```

## The End

Part 1 is [here](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e).

You can find the code [here](https://github.com/edyu/wtf-zig-zon-2).

Here are the code for [zig-duckdb](https://github.com/beachglasslabs/zig-duckdb) and [libduckdb](https://github.com/beachglasslabs/libduckdb).

Special thanks to [@InKryption](https://github.com/inkryption) for helping out on the new hack for the **Zig** package manager!

## ![Zig Logo](https://ziglang.org/zero.svg)
