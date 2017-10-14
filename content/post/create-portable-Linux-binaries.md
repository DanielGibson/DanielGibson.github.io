+++
date = "2017-07-22T15:37:57+02:00"
title = "How to create portable Linux binaries (with recent libstdc++)"
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

<!--*Note:* In this post, "portable" means that they work on most (hopefully all)
recent-ish Desktop Linux distributions with the same architecture (esp. x86, x86_64).

This post has a focus on videogames, but should apply to other kind of applications as well. -->

<!--more-->

Some general suggestions:

* Keep dependencies low - the fewer libs/frameworks you need the better
  * stb_image.h and stb_image_write.h are great alternatives to libPNG, libJPEG etc
  * there are lots of other handy easy-to-use header-only libs, see  
  ***TODO: Seans list***
* Bundle the libs you do need (note however potential problems described below)
  * Unless they're directly interacting with the system (like SDL or OpenAL),
    you can even link them statically if the license allows it
  * Don't link SDL or OpenAL or similar libs statically, so your users can
    easily replace your bundled libs in 5 years to get better support for the
    latest fads in window management, audio playback, ...  
    Ideally you only provide them as a fallback in case they're missing on the system
    (*ideally this post will show you how to do that*).
  * Same for cURL or OpenSSL - these regularly receive critical security updates
    so you should try to use the version on the users system
  * Don't try to statically link libc or libstdc++, this may cause trouble
    with other system libs you'll use (because the system libs dynamically link
    libc and maybe libstdc++ - probably in different versions you linked statically.
    That causes conflicts.)
* For libs with a C API, it is often feasible to use them with `dlopen()` and `dlsym()`
  instead of linking them.  
  This is useful for several reasons:
  * Your application can still run if the lib is missing (e.g. if you support multiple
    different sound systems, if the libs of one is missing that shouldn't make your application fail)
  * You avoid versioned symbols - as long as a function with a given name is available at all,
    you can use it - even if it has a different version than on the system you compiled on
  * If you use SDL2 yourself, it will do this for most system libs (esp. the graphics and sound related ones)  
    So if you choose to bundle SDL2, that will not cause many hard dependencies.
    * Linux distributions tend to build SDL2 in a way that explicitly links against all those libs,
      so indeed build SDL2 yourself; make sure to have the relevant development headers installed 
* Unfortunately, for C++ APIs this is not an option - another reason to prefer plain C libs :-)

## ***TODO: how to get libopenal version?***

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
Now (in 2017) using **Debian Wheezy** (old-oldstable from 2013) should
do the trick, it comes with glibc 2.13 and GCC 4.7.2 with corresponding libgcc 4.7.2
and libstdc++ 4.7.2 (GLIBCXX_3.4.17, CXXABI_1.3.6).  
It's lacking **SDL2**, but it's a good idea to build the latest version yourself
and bundle it with your game, so just do that and link against that.

This is all!  
...  
Well, *except* if you need a more recent compiler than GCC/G++ 4.7, because you
want to use C++11 (or even newer).

And this is where the trouble starts. Building a newer GCC version (I used 5.4.0)
yourself (on that old system/chroot) is easy enough - but that newer GCC version will
build its own libstdc++ and libgcc and the binaries you build with it will need these
newer versions. (Good news: At least the old libc will be good enough to link against.)

So you just bundle libstc++.so.6 and libgcc_s.so.1 from GCC 5.4.0 with your game, use
LD_LIBRARY_PATH (***TODO LINK TO DOCS***) or rpath $ORIGIN (***TODO LINK TO DOCS***)
to make sure your application uses those versions instead of those on the system and you're
done?

Of course it's never so easy.  
Your application (most probably) uses further system libs, like **libGL**, **libX**\*
(or the wayland equivalents) etc - and those system are most probably using libgcc or
even libstdc++.  
The Mesa (open source graphics drivers) libGL uses libstdc++, so I'll use
that to illustrate the problem (but, especially via libgcc, this problem can
occur with any other system lib as well):  
You have a 3D game and are using OpenGL for rendering. So you have to use the libGL
that is installed on your users system. Now imagine your user uses a bleeding edge
distribution like Arch Linux that always has very recent versions of everything,
including Mesa and GCC (and thus libstdc++ and libgcc), let's assume GCC 6.1.0.  
So their libGL expects libstdc++ 6.1.0, but you're making your game (and thus all
the libs it loads) use libstdc++ 5.4.0 - this results in a crash, because the
runtime linker can't find the libstdc++ 6.1.0 symbols the libGL is expecting.  
(*Note:* As libstdc++ and libgcc are backwards compatible, using newer libs
than the ones on the system libGL is linked against should not be a problem.
Apparently it is on RHEL and derivates like CentOS though, see ***TODO***.
I have no solution for that and hope that they'll fix it.)

So what you *want* is to only use your bundled libs if they're newer than the
ones on the system - and this decision has to be made *per lib*.
This means that rpath $ORIGIN is not an option (because you want to make the
decision which library path to use - system or your own - at runtime).  
This leaves the option of a wrapper setting LD_LIBRARY_PATH (if you need to
use the bundled versions). You'll need to put each of those libraries in a
different directory, so you can e.g. override libstdc++ but not libgcc.  
The wrapper will have to check which version of the lib is installed on the
system and which you provide and based on that either add an LD_LIBRARY_PATH
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

The wrapper will get the path to itself (***FIXME: link to DG_misc.h***)
and use that to get the full path to the bundled libs to check their versions,
then check the system libs versions and set LD_LIBRARY_PATH accordingly.  
Assuming your libstdc++ and libSDL2 are newer than the ones on the system, but
the systems libgcc is new enough, it'd look like like:  
`setenv("LD_LIBRARY_PATH", "/path/to/game/libs/stdcpp:/path/to/game/sdl2", 1);`  
(libgcc's API hasn't had any additions since GCC 4.8.0, so this is even likely).  
Afterwards it'd launch the actual application, like:  
`execv(/path/to/game/YourGame.real, argv);`  
where `argv` is the `argv` from the wrapper - they are just passed unchanged
*(you could change `argv[0]` to modify the name that will shop up in `ps`,
`top` etc, but that's purely cosmetical)*.

So what's missing? The wrappers implementation of course, especially the part
where we find out the version of a lib.  
Because *SDL2* is awesome, it has an easy API to get the version and getting it
is pretty simple (***TODO: LINK TO get_libsdl2_version()***).  
*libstdc++* and *libgcc* don't make it that easy. However, we *do* know
[what symbol versions exist](https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html#abi.versioning)
and can use that knowledge and:
 
* `objdump -T /path/to/libstdc++.so.6 | grep " DF .text" | grep GLIBCXX_3.4.21`  
  to get the symbols for that version, pick one (e.g. with the shortest name)
* in the wrapper load libstdc++ with `dlopen()`
* check if the chosen symbol is available with  
  `dlvsym(handle, "_ZNSt13runtime_errorC1EPKc", "GLIBCXX_3.4.21")`

*Note* that the symbol names are so ugly because they are C++ name mangled
and that the name mangling (and function signature) is different for different
architectures, so even for x86_64 and x86 the names are sometimes different,
for other architectures they may be completely different. Point is, you need
to look up the symbols for every CPU architecture you want to support.

Luckily I've already done all the hard work for x86 and x86_64 and libgcc
and libstdc++ (also SDL2) in [my wrapper](***FIXME: PATH TO WRAPPER***).  
It furthermore supports **libcurl**, but there the version isn't checked but only
if it's available on the system at all: Even if the systems version is older than
yours, it hopefully has recent security patches applied by the Linux distributor
and thus is favorable to your version that may have freshly discovered security
holes in a few months. You have to make sure to link against a libcurl.so.4
*without* versioned symbols though (or use it via `dlopen()` + `dlsym()` 
and don't link it at all).


<!--, the code is like
```c
typedef struct My_SDL2_version
{
    unsigned char major; // 2 in 2.0.5
    unsigned char minor; // 0 in 2.0.5
    unsigned char patch; // update version, e.g. 5 in 2.0.5
} My_SDL2_version;

  My_SDL2_version version = {0};
  // use just "libSDL2-2.0.so.0" for system version
  void* handle = dlopen("/path/to/game/sdl2/libSDL2-2.0.so.0", RTLD_LAZY);
  if(handle == NULL)
  {
    printf("couldn't dlopen() %s : %s\n", path, dlerror());
  }
  else
  {
    void (*sdl_getversion)(My_SDL2_version* ver);
    
    sdl_getversion = dlsym(handle, "SDL_GetVersion");
    if(sdl_getversion != NULL)
    {
      sdl_getversion(&version);
      printf("SDL2 version: %d.%d.%d\n", (int)version.major,
                 (int)version.minor, (int)version.patch);
    }
    
    dlclose(handle);
  }
```-->

<!--
To do anything useful, you'll have to use some libs of the users system.  
At least the **libc** (glibc, libc6.so.0) will be quite hard to avoid,
it implements the standard POSIX interface to the system for accessing files,
allocating memory, networking, threads etc. You'll also need **libgcc** - both
GCC and clang will implicitly link your executables and libs against it.  
If you're using C++ you'll (most probably) need **libstdc++**.

Then there are a plethora of X11 libs (**libX**\*) that are used to create windows
and display stuff in them and **libGL** for OpenGL (all these can be used via **libSDL2**
without explicitly linking against them, though).

Furthermore there are different libs to playback (or record) audio: libasound (ALSA),
pulse audio etc - again **libSDL2** can abstract those; **libopenal** gives you a
higher level interface for 3D audio.

Most of these libs use *versioned symbols*: ***TODO: DESCRIPTION***  
They are backwards compatible (in case of libc, libgcc and libstdc++ for all versions
released in the last 15years or so), but not necessarily forwards compatible.  
This means: If you link your binaries against older versions of the libs, they will
work with all newer versions (until they break backwards compatibility which doesn't
happen often) - but if you link against a newer version of the libs, the binaries will
**not** work with older versions of them.-->

# Building a portable libcurl.so.4

Often you'd like to use HTTP or HTTPS and most common library to do that on Linux
is libcurl. It also supports a plethora of other protocols, but I usually deactivate
everything but http(s).  
As mentioned before, you want a libcurl with _**un**versioned_ symbols to link against
(but the libcurl in most Linux distros uses symbol versioning), so that's one reason
to build it yourself.  
Another is that by default it links against OpenSSL, and libssl is not backwards compatible,
so you'd have to ship that in addition to libcurl.. not fun. Fortunately libcurl
supports several other SSL/TLS libraries, including [mbed TLS](https://tls.mbed.org/)
which is easy to build and can be statically linked.

## Building mbed TLS (tested with 2.6.0)

* Download and extract the source
* Edit Makefile, change DESTDIR to something else, I'll use /opt/mbedtls/
* Build mbedtls: `make SHARED=1 -j4`
  - Even though I want to link statically, I build with `SHARED=1` so it gets
    built with `-fPIC` - this is needed, as it will be used in a shared library (libcurl.so.4)
* Install it `sudo make install` (or without sudo if DESTDIR is writable by your current user)
* Remove the dynamic mbedtls libs to make sure it will get statically linked by libcurl:
  - `sudo rm /opt/mbedtls/lib/*.so`
  - `sudo rm /opt/mbedtls/lib/*.so.*`

## Building cURL itself

Now you can build libcurl itself (this was tested with 7.56).

First you download and extract the source, of course.  

libcurl will need CA certificates to verify the SSL certificates from HTTPS.
libcurl packages from Linux distributions are configured to look for them
in the system, but for a portable libcurl this is not an option (the path
to the certificate varies across distributions).  
Luckily cURL offers a cert "bundle" (from Mozilla) for download and can even
compile it in. Download that bundle from https://curl.haxx.se/ca/cacert.pem 
(If you need a custom CA certificate for self-signed certificates, you can add
it to that file)

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
Copy `/opt/curl/lib/libcurl.so.4` to `/path/to/game/libs/curl/` so the wrapper
can use it if libcurl is not found on your users system.
