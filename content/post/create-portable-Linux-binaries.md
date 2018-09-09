+++
date = "2017-11-26T23:12:23+02:00"
title = "How to create portable Linux binaries (even if you need a recent compiler)"
slug = "creating-portable-linux-binaries"
tags = [ "C", "C++", "programming", "gamedev" ]
draft = false
toc = true
ghcommentid = 12
+++

Creating application binaries for Linux that run on a wide range of distributions
is a bit tricky, as different distributions ship different versions of various
system libraries. These are usually backwards compatible, but not forwards
compatible, so programs linked against older versions of the libraries also
work with newer versions, but not (necessarily) the other way around.  
So you want to link your application against older versions of those libs;
however, especially when using C++11 or newer, this is not always feasible.

This post will show how to deal with these issues. It has a focus on videogames,
but the general ideas apply to other kinds of applications as well (with normal GUI
applications you may have more or more complex dependencies like Qt which may need
extra care that is not detailed here).

I also somehow ended up writing a short introduction into dynamic libraries and
symbol versioning on Linux (last section of the article).

<!--more-->

# Some general suggestions

* Keep dependencies low - the fewer libs/frameworks you need the better
  * [stb_image.h and stb_image_write.h](https://github.com/nothings/stb)
    are great alternatives to libPNG, libJPEG etc
  * there are lots of other handy easy-to-use header-only libs; many are listed at
    https://github.com/nothings/single_file_libs
* Bundle the libs you do need (note however potential problems described below)
  * Unless they're directly interacting with the system (like SDL or OpenAL),
    you can even link them statically if the license allows it
  * Don't link SDL or OpenAL or similar libs statically, so your users can
    easily replace your bundled libs in 5 years to get better support for the
    latest fads in window management, audio playback, ...[^fn:fallback]
  * Same for cURL: It regularly receives critical security updates so you should
    try to use the version on the users system. You should however _**not** link_
    against the system libcurl (more details on this below).
  * Don't try to statically link libc or libstdc++, this may cause trouble
    with other system libs you'll use (because the system libs dynamically link
    libc and maybe libstdc++ - probably in versions different from what you
    linked statically. That causes conflicts.)
* For libs with a C API, it is often feasible to use them with `dlopen()` and `dlsym()`
  instead of linking them.  
  This is useful for several reasons:
  * Your application can still run if the lib is missing (e.g. if you support multiple
    different sound systems, if the lib of one is missing that shouldn't make your application fail)
  * You avoid versioned symbols[^fn:versym] - as long as a function with a given name is available at all,
    you can use it - even if it has a different version than on the system you compiled on
  * If you build SDL2 yourself, it will by default do this for most system libs (esp. the graphics and sound related ones).
    So if you choose to bundle SDL2, that will not cause many hard dependencies.
     * Linux distributions tend to build SDL2 in a way that explicitly links against all those libs,
       so indeed build SDL2 yourself; make sure to have the relevant development headers installed 
* Unfortunately, for C++ APIs `dlopen()` + `dlsym()` is not an option - another reason to prefer plain C libs :-)
  * If you end up using libs with a C++ API and they're not header-only anyway, bundle them,
    maybe even link them statically. If that's not feasible, don't use them.  
    GCC (g++) broke ABI compatibility of C++ libs (except for libstdc++ apparently) with GCC 5.1
    by introducing ["ABI tags"](https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html).
    This can also affect libraries built with some g++ vs clang++ versions;
    clang introduced support for ABI tags in [version 3.9](http://releases.llvm.org/3.9.0/tools/clang/docs/ReleaseNotes.html#id4).

# Basic system libraries

The most basic system libs you can hardly avoid are:

* **libc** (glibc: libc.so.6, libm.so.6, librt.so.1, libresolv.so.2, libpthread.so.0
  and many more) it implements the C standard lib and  standard POSIX interface to
  the system for accessing files, allocating memory, networking, threads etc.
* **libgcc** (libgcc_s.so.1) both GCC and clang use it for various internal things
  and will implicitly link your executables and libs against it if needed.  
* (For C++) **libstdc++** (libstdc++.so.6), `g++` and `clang++` will implicitly
  link against it.

To work with all (or at least most) Linux distributions released in the last years,
you need to link against reasonably old versions of those libs.  
The easiest way to do that is by building on an old distribution (in a chroot or VM).
Now (in 2017) using **Debian 7 "Wheezy"** (old-oldstable from 2013) should
do the trick, it comes with glibc 2.13 and GCC 4.7.2 with corresponding libgcc 4.7.2
and libstdc++ 4.7.2 (GLIBCXX_3.4.17, CXXABI_1.3.6).  
Wheezy is lacking **SDL2**, but it's a good idea to build the latest version yourself
and bundle it with your game anyway, so just do that and link against that.

This is all! Or is it?

# But what if I need a (more) recent compiler?

If you need a more recent compiler than GCC/G++ 4.7, for example because you
need C++11 (or even newer) features not supported by GCC 4.7, this is not enough..

And this is where the trouble starts. Building a newer GCC version (I used 5.4.0)
yourself (on that old system/chroot) is easy enough - but that newer GCC version will
build its own libstdc++ and libgcc and the binaries you build with it will need these
newer versions. (Good news: At least the old libc will be good enough to link against.)

So you just bundle libstc++.so.6 and libgcc_s.so.1 from GCC 5.4.0 with your game, use
[LD_LIBRARY_PATH](http://man7.org/linux/man-pages/man8/ld.so.8.html) or
rpath $ORIGIN (see [manpage](http://man7.org/linux/man-pages/man1/ld.1.html) and
[this article](http://longwei.github.io/rpath_origin/)) to make sure your application
uses those versions instead of those on the system and you're done?

Of course it's never so easy.  
Your application (most probably) uses further system libs, like **libGL**, **libX**\*
(or the wayland equivalents) etc - and those system libs are most probably using
libgcc or even libstdc++.  
The Mesa (open source graphics drivers) libGL uses libstdc++, so I'll use
that to illustrate the problem (but, especially via libgcc, this problem can
occur with any other system lib as well):

> You have a 3D game and are using OpenGL for rendering. So you have to use the libGL
> that is installed on your users system. Now imagine your user uses a bleeding edge
> distribution like Arch Linux that always has very recent versions of everything,
> including Mesa and GCC, let's assume GCC 7.2.0.  
> So their libGL expects libstdc++ 7.2.0, but you're making your game (and thus all
> the libs it loads) use libstdc++ 5.4.0 - this results in a crash, because the
> runtime linker can't find the libstdc++ 7.2.0 symbols the libGL is expecting.  
> (*Note:* As libstdc++ and libgcc are backwards compatible, using newer libs
> than the ones on the system libGL is linked against should not be a problem.[^fn:rhel])

So what you *want* is to only use your bundled libs if they're newer than the
ones on the system - and this decision has to be made *per lib*.
This means that `rpath $ORIGIN` is not an option (because you want to make the
decision which library path to use - system or your own - at runtime).

# A wrapper that selectively overrides system libs

This leaves the option of a wrapper setting `LD_LIBRARY_PATH` (if you need to
use the bundled versions). You'll need to put each of those libraries in a
different directory, so you can e.g. override libstdc++ but not libgcc.  
The wrapper will have to check which version of the lib is installed on the
system and which you provide and based on that either add an `LD_LIBRARY_PATH`
entry or not. Nice side-effect: Once you have such a wrapper, you can also
easily use it for other libs like SDL2 as well - as long as you have a way
to check the library versions.  
This wrapper is ideally written in plain C (without further dependencies)
and compiled with the standard GCC version of your build system/chroot
(i.e. **not** the updated GCC you compiled yourself). The whole thing will look
somehow like this:

* /path/to/game/
  * YourGame (the wrapper)
  * YourGame.real (the actual executable of your application)
  * libs/
     * stdcpp/
         * libstdc++.so.6
     * gcc/
         * libgcc_s.so.1
     * sdl2/
         * libSDL2-2.0.so.0
     * curl/
         * libcurl.so.4
  * ...

The wrapper will get the path to itself (for example with
[this handy function](https://github.com/DanielGibson/Snippets/blob/d1e63fee882c108b6fe391db03ef5d1c3345d45a/DG_misc.h#L65-L68))
and use that to get the full path to the bundled libs to check their versions,
then check the system libs versions and set `LD_LIBRARY_PATH` accordingly.  
Assuming your libstdc++ and libSDL2 are newer than the ones on the system, but
the systems libgcc is new enough, it'd look like like:  
`setenv("LD_LIBRARY_PATH", "/path/to/game/libs/stdcpp:/path/to/game/libs/sdl2", 1);`  
(libgcc's API hasn't had any additions since GCC 4.8.0, so this is even likely).  
Afterwards it'd launch the actual application, like:  
`execv(/path/to/game/YourGame.real, argv);`  
where `argv` is the `argv` from the wrapper - it's just passed unchanged.[^fn:argv]

So what's missing? The wrappers implementation of course, especially the part
where it finds out the version of a lib.

## Some implementation details of the wrapper

_If you don't care about the implementation details just skip this section.
You can find the wrapper itself [**in this Github project**](https://github.com/DanielGibson/Linux-app-wrapper/)._

Because *SDL2* is awesome, it has an easy API to get the version and getting it is
[pretty simple](https://github.com/DanielGibson/Linux-app-wrapper/blob/6971a1a2a8b3d9f57e9e93c32c25c8c861750027/wrapper.c#L273-L304).
*libstdc++* and *libgcc* don't make it that easy - however, we *do* know
[what symbol versions exist](https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html#abi.versioning)
and can use that knowledge and:
 
* `objdump -T /path/to/libstdc++.so.6 | grep " DF .text" | grep GLIBCXX_3.4.21`  
  to get a list of symbols libstdc++ exports for that version and pick one
  (e.g. with the shortest name)[^fn:fnlist]
* in the wrapper load libstdc++ with `dlopen()`
* check if the chosen symbol is available with  
  `dlvsym(handle, "_ZNSt13runtime_errorC1EPKc", "GLIBCXX_3.4.21")`[^fn:checkversion]
  
<!-- ***TODO: how to get libopenal version?*** -->

*Note* that the symbol names are so ugly because they are C++ name mangled
and that the name mangling (and function signature) is different for different
architectures, so even for x86_64 and x86 the names are sometimes different,
for other architectures they may be completely different. Point is, you need
to look up the symbols for every CPU architecture you want to support.[^fn:OScc]  
For `libgcc` the symbols look nicer (as it's a plain C lib), and symbol names
*should* be the same on x86 vs x86_64. However, some symbols (usually functions)
don't exist on all CPU architectures, so you still gotta check both the 32bit
and 64bit version of the libs.

Lucky for you, I've already done all that work for x86 and x86_64 and libgcc
and libstdc++ (also SDL2) in [**my wrapper**](https://github.com/DanielGibson/Linux-app-wrapper).  
It furthermore supports **libcurl**, but there the version isn't checked but only
if it's available on the system at all: Even if the systems version is older than
yours, it hopefully has recent security patches applied by the Linux distributor
and thus is favorable to your version that may have freshly discovered security
holes in a few months. You have to make sure to link against a libcurl.so.4
*without* versioned symbols[^fn:versym] though (or use it via `dlopen()` + `dlsym()` 
and don't link it at all).

# Building a portable libcurl.so.4 without versioned symbols

Often you'd like to use HTTP or HTTPS and the most common cross-platform
library to do that is libcurl. It also supports a plethora of other protocols,
but I usually deactivate everything but http(s).
As mentioned before, you want a libcurl with
_**un**versioned_ symbols to link against (but the libcurl in most Linux distros
uses symbol versioning), so that's one reason to build it yourself.  
Another is that by default it links against OpenSSL, and libssl is not backwards compatible,
so you'd have to ship that in addition to libcurl.. not fun. Fortunately libcurl
supports several other SSL/TLS libraries, including [mbed TLS](https://tls.mbed.org/)
which is easy to build, has a friendly license
([Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0))
and can be statically linked.

## Building mbed TLS (tested with 2.6.0)

* Download and extract the source
* Edit Makefile, change `DESTDIR` to something else, I'll use `/opt/mbedtls/`
* Build mbedtls: `make SHARED=1 -j4`
  - Even though I want to link statically, I build with `SHARED=1` so it gets built with  
    `-fPIC` - this is needed, as it will be used in a shared library (libcurl.so.4)
* Install it: `sudo make install` (or without sudo if DESTDIR is writable by your current user)
* Remove the dynamic mbedtls libs to make sure it will get statically linked by libcurl:
  - `sudo rm /opt/mbedtls/lib/*.so`
  - `sudo rm /opt/mbedtls/lib/*.so.*`

## Building libcurl itself

Now you can build libcurl itself (this was tested with 7.56).

First you download and extract the source, of course.  

libcurl will need CA certificates to verify the SSL certificates from HTTPS.
libcurl packages from Linux distributions are configured to look for them
in the system, but for a portable libcurl this is not an option (the path
to the certificate varies across distributions).  
Luckily cURL offers a cert "bundle" (from Mozilla) for download and can even
compile it in. Download that bundle from https://curl.haxx.se/ca/cacert.pem 
(If you need a custom CA certificate for self-signed certificates, you can add
it to that file).

Then you execute the `./configure` script with all the options..  

```text
./configure --prefix=/opt/curl/ --enable-http --disable-ftp --disable-ldap \
  --disable-file --disable-ldaps --disable-telnet --disable-rtsp \
  --disable-dict --disable-tftp --disable-pop3 --disable-imap \
  --disable-smb --disable-smtp --disable-gopher --without-libssh2 \
  --without-librtmp --disable-versioned-symbols --without-ssl \
  --with-mbedtls=/opt/mbedtls --with-ca-bundle=/path/to/cacert.pem
```

`--prefix=/opt/curl/` sets the installation directory, then there's tons of
options to disable protocols I don't care about (if you want any of them just
leave out the corresponding `--disable-*`), `--disable-versioned-symbols`
makes sure the libcurl symbols are not versionsed with the used SSL library name
(Linux distributions often do that, see [below](#how-and-why-libcurl-uses-symbol-versioning)
 for a guess why they do it), `--without-ssl` disables the usage of OpenSSL,
`--with-mbedtls=/opt/mbedtls` enables usage of mbed TLS and sets where to
find mbedtls (see `DESTDIR` from mbed TLS above)
and `--with-ca-bundle` sets the path of the CA certificate bundle downloaded earlier.

Now build it with `make -j4` and install it with `sudo make install`.

Make sure your application links against that (`-L /opt/curl/lib`) instead of
the system libcurl to make sure your application uses unversioned symbols.  
Copy `/opt/curl/lib/libcurl.so.4` to `/path/to/wrapper/libs/curl/` so the wrapper
can use it if libcurl is not found on your users system.

# Bonus: Dynamic Libs on Linux and what is symbol versioning?

I wish I just could have linked some article with a nice introduction/overview
about symbol versioning on Linux, but I couldn't find any..  

## Dynamic Libraries on Unix-like systems

Let's start with a short overview of what "dynamic libraries" are and how
they are used on Unix-like systems.

First: **What are dynamic libraries** (aka "shared objects")? They're the Unix equivalent
of DLLs and usually have the file-extension `.so` (`.dylib` on OSX).[^fn:libswiki]
They "export" "symbols" that can be used by programs or other libraries.

Second: **What are symbols?** Symbols are things libraries "export" for users of the library,
so first and foremost it's functions.[^fn:symexp] It could also be global variables, but
I think for this explanation it's easiest to just think about functions.

There are basically two ways to use a library (and its exported functions):

1. Link against the library (like `gcc -o YourApp yourapp.c -lyourlib`).  
   This is called **dynamic _linking_**. When executing YourApp the "runtime linker"
   (aka "dynamic linker" - [`ld.so`](http://man7.org/linux/man-pages/man8/ld.so.8.html) on Linux)
   looks for  the libs is was linked against (in this case `libyourlib.so` or maybe
   `libyourlib.so.0` or similar[^fn:soname]), makes sure the lib exports all the
   functions of that lib that you're using and makes sure you calls to those
   functions actually call the ones in the lib.  
   If any of the required libraries or functions in the libraries can't be found,
   it produces an error and your application won't start.
2. Load the library with  
   `void* libhandle = dlopen("yourlib.so.0", RTDL_LAZY);`  
   get a pointer to an exported function with  
   `int(*fnpointer)(float) = dlsym(libhandle, "function_name");`  
   and use that function pointer to call the function, like  
   `int x = fnpointer(42.0f);`  
   This is called **dynamic _loading_**. If `yourlib.so.0` couldn't be found,
   [**dlopen()**](http://man7.org/linux/man-pages/man3/dlopen.3.html)
   just returns `NULL`, similarly if `function_name` couldn't be found
   [**dlsym()**](http://man7.org/linux/man-pages/man3/dlsym.3.html)
   returns `NULL`, so *dynamic loading*, unlike *dynamic linking*,
   allows the application developer to handle a missing
   library or function within a library in a non-fatal way.  
   Furthermore, `dlopen()` can be called with a path to a dynamic library
   (instead of just the library name), which allows the application to select
   the path, which is more flexible than what the *runtime linker* can do.

Both the *runtime linker* and `dlopen()` (if called with just the library name without a path)
look for libraries in several directories, including those set via `rpath` in the executable,
with the `LD_LIBRARY_PATH` environment variable and several system specific directories
the runtime linker knows about.
The [runtime linker manpage](http://man7.org/linux/man-pages/man8/ld.so.8.html)
covers this in more detail.

## Versioned Symbols

*__Note:__ This is pretty Linux specific. Apparently other operating systems like
[FreeBSD](https://people.freebsd.org/~deischen/symver/library_versioning.txt)
and [Solaris](https://docs.oracle.com/cd/E19683-01/816-5042/solarisabi-8/index.html)
support some kind of symbol versioning as well, but details may vary.
So maybe the things I describe here are similar on other Unix-like systems, maybe not.*

Symbol Versioning associates a symbol (for simplicity from here on I'll write "function"
instead, but the same applies to other kinds of exported symbols) with a version
(represented as a string, like "GLIBC_2.2.5").
When using such a function the (compile-time) linker will not only link against
the function-name, but also the version.  
The **runtime-linker** will then make sure that your application will get the right
function (right name + right version) from  a dynamic library - if that is not
available, it will fail.

[**dlsym()**](http://man7.org/linux/man-pages/man3/dlsym.3.html) on the other
hand just ignores the version and will (usually[^fn:dlsymdefault]) return the
*default* function pointer for the given name, regardless of version.
At least Linux (and FreeBSD, even though their manpage doesn't mention it) has a
[**dlvsym()**](http://man7.org/linux/man-pages/man3/dlsym.3.html) function,
that additionally takes the version name as an argument, like  
`int(*fnpointer)(float) = dlvsym(libhandle, "function_name", "VERSION_NAME");`  
As you'd expect, it returns the function for `function_name` with version `VERSION_NAME`
and if that combination couldn't be found it returns NULL; even if a function called
`function_name` with another version (or none at all) exists.

### Example: glibc's memcpy()

Being a C standard lib, glibc of course always had a
[**memcpy()**](http://man7.org/linux/man-pages/man3/memcpy.3.html) implementation.
Historically, it used to behave like [**memmove**](http://man7.org/linux/man-pages/man3/memmove.3.html),
i.e. it supported overlapping source and destination memory ranges.  
For glibc version 2.14, the developers introduced optimizations for
`memcpy()` that make it faster, but don't work with overlapping memory ranges.
Thankfully, they decided to use a symbol version so this change doesn't break
old binaries that (incorrectly) rely on `memcpy()` working with overlapping ranges,
but only breaks code that's recompiled and linked against glibc 2.14 (or newer).[^fn:memcpy]

```text
$ readelf -s /lib/x86_64-linux-gnu/libc.so.6 | grep memcpy
...
1132: 00000000000943f0 106 IFUNC GLOBAL DEFAULT 13 memcpy@@GLIBC_2.14
1134: 000000000008f14b  87 IFUNC GLOBAL DEFAULT 13 memcpy@GLIBC_2.2.5
...
```

As expected, `memcpy` indeed turns up twice in the symbols of `libc.so.6` - once
in version `GLIBC_2.2.5`[^fn:glibc225] and once in version `GLIBC_2.14`.  
You'll also note that before `GLIBC_2.2.5` is one `@` and before `GLIBC_2.14`
there are two `@@` - the two `@@` indicate that this is the default version
of that function that the compile-time linker (and apparently `dlsym()`[^fn:dlsymdefault]) will use.

### How and why libcurl uses symbol versioning

**libcurl** uses symbol versioning in a different way: There all symbols get the same
version and only exist in one version (if it was built with symbol versioning enabled).
The version name depends on the SSL/TLS library it's linked against - for
OpenSSL it's `CURL_OPENSSL_3`, for GNU TLS it's `CURL_GNUTLS_3`,
e.g. `curl_easy_init@@CURL_OPENSSL_3` vs `curl_easy_init@@CURL_GNUTLS_3`.
This means that if an application is linked against an OpenSSL libcurl,
it won't work with a GNU TLS libcurl.

While the most commonly used parts of libcurl are completely independent of the
underlying SSL/TLS implementation, it ***does*** have a few options
that allow you to set SSL/TLS-backend specific options or even callbacks,
like [CURLOPT_SSLENGINE](https://curl.haxx.se/libcurl/c/CURLOPT_SSLENGINE.html) or
[CURLOPT_SSL_CTX_FUNCTION](https://curl.haxx.se/libcurl/c/CURLOPT_SSL_CTX_FUNCTION.html)
and [CURLOPT_SSL_CTX_DATA](https://curl.haxx.se/libcurl/c/CURLOPT_SSL_CTX_DATA.html).  
So to ensure greater robustness this kinda makes sense..

However, unless you use those (or other similar things), it should be safe
to ignore the symbol versions by compiletime-linking against an unversioned libcurl
(as shown [above](#building-a-portable-libcurl-so-4-without-versioned-symbols);
so your application works with any libcurl) or by loading it and its
functions with `dlopen()` + `dlsym()`.

### More information on Symbol Versioning

This was a very rough overview, if you want to learn more, look at:

* [Short Article on exporting versioned symbols in a library](https://www.technovelty.org/c/symbol-versions-and-dependencies.html)
* [GNU ld documentation on VERSION Scripts](https://sourceware.org/binutils/docs-2.20/ld/VERSION.html) -
  those are used to define the versions; also explains how to assign versions to functions
* [Ulrich Drepper: How To Write Shared Libraries](https://www.akkadia.org/drepper/dsohowto.pdf)
  (especially chapters 3.3-3.7)
* [Ulrich Drepper on ELF Symbol Versioning](https://www.akkadia.org/drepper/symbol-versioning) -
  More low-level details
* [Symbol Versioning on FreeBSD](https://people.freebsd.org/~deischen/symver/library_versioning.txt)
* [Symbol Versioning on Solaris](https://docs.oracle.com/cd/E19683-01/816-5042/solarisabi-8/index.htm)


<!-- Below: Footnotes -->

[^fn:fallback]: Ideally the bundled version will only be used as a fallback in case
    the lib is missing on the system. *You're lucky, this post will show you how to do
    that at least for SDL.* For OpenAL it's not as easy, as up to now there has been no
    good, portable way to get the version of the system `libopenal.so.1`, at least not without
    creating a full OpenAL context and using `alGetString(AL_VERSION);`. However OpenAL-soft's
    awesome maintainer *KittyCat* has added an "un-exposed" function accessible via `dlsym()`
    that returns the same thing as `alGetString(AL_VERSION)`, but without needing any context,
    called `alsoft_get_version()`, see [this commit](https://github.com/kcat/openal-soft/commit/2f5b86dd381ac36d09951e05777ccb97237fa06e)
    - so future versions (probably from 1.19 on?) can be detected that way.  
    (Yes, this is a nonstandard OpenAL-soft only thing, but I don't think any other OpenAL
     implementation is relevant on Linux.)

[^fn:versym]: [See the bonus section](#bonus-dynamic-libs-on-linux-and-what-is-symbol-versioning)
    for an explanation of/introduction into versioned symbols/symbol versioning.

[^fn:rhel]: Apparently it is on **Red Hat Enterprise Linux (RHEL)** and
    derivates like **CentOS** though, because they *statically* link `libstdc++`,
    see [this bugreport](https://bugzilla.redhat.com/show_bug.cgi?id=1417663).
    I have no solution for that problem and hope that Red Hat will fix it.  
    **Fedora** does the same as far as I know, but there it's *less of a problem*,
    because Fedora has frequent releases and ships recent versions of libs,
    so unless you're shipping a very bleeding edge libstdc++ (or the user
    runs a very old version of Fedora), the system version will be at least
    as new as yours and the yet to be introduced wrapper will choose
    the system version instead.

[^fn:argv]: You could change `argv[0]` to modify the name that will show up in `ps`,
    `top` etc, but that's purely cosmetical.

[^fn:fnlist]: my table with function- and version-names for libstdc++ looks like
    [this](https://github.com/DanielGibson/Linux-app-wrapper/blob/6971a1a2a8b3d9f57e9e93c32c25c8c861750027/wrapper.c#L176-L210)
    and for libgcc it looks like
    [this](https://github.com/DanielGibson/Linux-app-wrapper/blob/6971a1a2a8b3d9f57e9e93c32c25c8c861750027/wrapper.c#L242-L263).

[^fn:checkversion]: the tables mentioned in[^fn:fnlist] are used like
    [this](https://github.com/DanielGibson/Linux-app-wrapper/blob/6971a1a2a8b3d9f57e9e93c32c25c8c861750027/wrapper.c#L97-L126)

[^fn:OScc]: The names could also be different for different Operating Systems,
    as they might use different calling- and naming conventions.  
    So while this general concept should work on other Unix-like systems
    like \*BSD, Solaris or maybe even OSX, the names might be different - and
    they might not even use libstdc++ but e.g. clang's libc++.

[^fn:libswiki]: [Wikipedia has some more information about libraries and shared libraries](https://en.wikipedia.org/wiki/Library\_\(computing\)#Shared_libraries)

[^fn:symexp]: Not only libraries, but also executables can export symbols - that way
    libraries loaded by the executable can use symbols of the executable.  
    The relevant concept for selecting which symbols are exported is called
    ["symbol visibilty"](https://www.technovelty.org/code/why-symbol-visibility-is-good.html)  
    On Linux (and AFAIK all other Unix-like systems) all symbols are exported by default,
    unless you compile with `-fvisibility=hidden`, then only functions/globals specifically
    marked (see linked article) are exported (on Windows it's the other way around, there
    symbols are not exported by default).

[^fn:soname]: You always link against libfoo.so, but sometimes the lib the runtime linker
    is actually looking for has a slightly different name, like libfoo.so.1 
    The relevant thing is called [**soname**](https://en.wikipedia.org/wiki/Soname)

[^fn:memcpy]: [People were not very happy with this change anyway](http://www.win.tue.nl/~aeb/linux/misc/gcc-semibug.html)

[^fn:glibc225]: This is the oldest/lowest symbol version in `libc.so.6`,
    so I guess they started symbol versioning in glibc 2.2.5.

[^fn:dlsymdefault]: While apparently `dlsym(RTLD_DEFAULT, "fun")` and `dlsym(libhandle, "fun")`
    return the default version of `fun()`, it seems like `dlsym(RTLD_NEXT, "fun")`
    returns the *oldest* version...  
    Note that I make these statements based on observation, I'm not sure if there
    is a defined behavior for this and what it looks like (couldn't find any
    documentation on this). Observations:

    * That `dlsym(RTLD_NEXT, "fun")` returns the oldest version seems odd to me
      and there is [a 5 years old bugreport on glibc about this](https://sourceware.org/bugzilla/show_bug.cgi?id=14932).
      I wouldn't rely on this behavior.
    * For `RTLD_DEFAULT` I could imagine both using the default version **or**
      (if it's from a library the executable is linked against) the version
      version the executable was linked against. Not sure how practical that
      is though, especially for symbols that the executable doesn't use "directly"..
      So *maybe* it only makes sense to return the default version of the actual lib here
    * When passing a library handle (from `dlopen()`), IMHO it only makes sense
      to return the default version of the function (as it appears to be the case)

    If anyone knows more about this, please leave a comment!

    Note that symbol versioning is not only used for cases like memcpy(), where
    at least the function signature stayed the same, but is also used for
    functions that changed their signature, i.e. `VERSION1` takes arguments of
    different type than `VERSION2`. In that case it's of course important to
    get the right version and using `dlvsym()` is a good idea..

