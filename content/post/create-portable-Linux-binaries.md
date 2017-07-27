+++
date = "2017-07-22T15:37:57+02:00"
title = "How to create portable Linux binaries (with recent libstdc++)"
tags = [ "C", "C++", "programming", "gamedev" ]
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
* Bundle the libs you do need (note however potential problems describe below)
  * Unless they're directly interacting with the system (like SDL or OpenAL),
    you can even link them statically if the license allows it
  * Don't link SDL or OpenAL or similar libs statically, so your users can
    just replace your bundled libs in 5 years to get better support for the
    latest fads in Window management, audio playback, ...  
    Ideally you only provide them as a fallback in case they're missing on the system
  * Same for cURL or OpenSSL - these regularly receive critical security updates
    so you should try to use the version on the users system
  * Don't try to statically link libc or libstdc++, this may cause trouble
    with other system libs

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
**not** work with older versions of them.

