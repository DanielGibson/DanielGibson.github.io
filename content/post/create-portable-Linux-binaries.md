+++
date = "2017-10-16T01:45:57+02:00"
title = "How to create portable Linux binaries (even if you use C++11 or newer)"
tags = [ "C", "C++", "programming", "gamedev" ]
draft = true
# ghcommentid = 12
+++

Creating binaries for Linux that run on a wide range of distributions is
a bit tricky, as different distributions ship different versions of various
system libraries. These are generally backwards compatible, but not forwards
compatible, so programs linked against older versions of the libraries also
work with newer versions, but not (necessarily) the other way around.  
So you want to link your application against older versions of those libs;
however, especially when using C++11 or newer, this is not always feasible.

This post will show how to deal with these issues. It has a focus on videogames,
but the general ideas apply to other kinds of applications as well (with normal GUI
applications you may have more or more complex dependencies like Qt which may need
extra care that is not detailed here).

<!--more-->

## Some general suggestions

* Keep dependencies low - the fewer libs/frameworks you need the better
  * stb_image.h and stb_image_write.h are great alternatives to libPNG, libJPEG etc
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
  * You avoid versioned symbols - as long as a function with a given name is available at all,
    you can use it - even if it has a different version than on the system you compiled on
  * If you use SDL2 yourself, it will do this for most system libs (esp. the graphics and sound related ones).
    So if you choose to bundle SDL2, that will not cause many hard dependencies.
     * Linux distributions tend to build SDL2 in a way that explicitly links against all those libs,
       so indeed build SDL2 yourself; make sure to have the relevant development headers installed 
* Unfortunately, for C++ APIs `dlopen()` + `dlsym()` is not an option - another reason to prefer plain C libs :-)

## Basic system libraries

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

## But what if I need a (more) recent compiler?

If you need a more recent compiler than GCC/G++ 4.7, because you
want to use C++11 (or even newer), this is not enough..

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
(or the wayland equivalents) etc - and those system are most probably using libgcc or
even libstdc++.  
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

## A wrapper that selectively overrides system libs

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
`setenv("LD_LIBRARY_PATH", "/path/to/game/libs/stdcpp:/path/to/game/sdl2", 1);`  
(libgcc's API hasn't had any additions since GCC 4.8.0, so this is even likely).  
Afterwards it'd launch the actual application, like:  
`execv(/path/to/game/YourGame.real, argv);`  
where `argv` is the `argv` from the wrapper - it's just passed unchanged.[^fn:argv]

So what's missing? The wrappers implementation of course, especially the part
where it finds out the version of a lib.

### Some implementation details of the wrapper

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
*without* versioned symbols though (or use it via `dlopen()` + `dlsym()` 
and don't link it at all).

## Building a portable libcurl.so.4 without versioned symbols

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

### Building mbed TLS (tested with 2.6.0)

* Download and extract the source
* Edit Makefile, change `DESTDIR` to something else, I'll use `/opt/mbedtls/`
* Build mbedtls: `make SHARED=1 -j4`
  - Even though I want to link statically, I build with `SHARED=1` so it gets built with  
    `-fPIC` - this is needed, as it will be used in a shared library (libcurl.so.4)
* Install it: `sudo make install` (or without sudo if DESTDIR is writable by your current user)
* Remove the dynamic mbedtls libs to make sure it will get statically linked by libcurl:
  - `sudo rm /opt/mbedtls/lib/*.so`
  - `sudo rm /opt/mbedtls/lib/*.so.*`

### Building libcurl itself

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
(Linux distros do that, I have no idea what it's good for), `--without-ssl`
disables the usage of OpenSSL, `--with-mbedtls=/opt/mbedtls` enables usage of
mbed TLS and sets where to find mbedtls (see `DESTDIR` from mbed TLS above)
and `--with-ca-bundle` sets the path of the CA certificate bundle downloaded earlier.

Now build it with `make -j4` and install it with `sudo make install`.

Make sure your application links against that (`-L /opt/curl/lib`) instead of
the system libcurl to make sure your application uses unversioned symbols.  
Copy `/opt/curl/lib/libcurl.so.4` to `/path/to/wrapper/libs/curl/` so the wrapper
can use it if libcurl is not found on your users system.


[^fn:fallback]: Ideally the bundled version will only be used as a fallback in case
    the lib is missing on the system (*you're lucky, this post will show you how to do
    that at least for SDL*).

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
