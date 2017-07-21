+++
date = "2015-03-23T00:06:18"
title = "Comparing Performance: stb_image vs libjpeg(-turbo), libpng and lodepng"
tags = [ "C", "jpeg", "libjpeg-turbo", "libpng", "Linux", "lodepng", "performance", "png", "programming", "stb_image" ]
ghcommentid = 9
+++

I recently tried out Sean Barrett's [stb_image.h](https://github.com/nothings/stb/blob/master/stb_image.h)
and was blown away by how fucking easy it is to use.  
Integrating it into your project is trivial: Just add the header and somewhere do:

```c
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
```

That's all. (If you wanna use it in multiple files you just `#include "stb_image.h"` there without the `#define`.)

And the API is trivial too:

```c
int width, height, bytesPerPixel;
unsigned char *pixeldata, *pixeldata2;
pixeldata = stbi_load("bla.jpg", &width, &height, &bytesPerPixel, 0);
// if you have already read the image file data into a buffer:
pixeldata2 = stbi_load_from_memory(bufferWithImageData, bufferLength,
                                   &width, &height, &bytesPerPixel, 0);
if(pixeldata2 == NULL)
    printf("Some error happened: %s\n", stbi_failure_reason());
```

There's also a simple callback-API which allows you to define some callbacks that stb_image will call to get the data, handy if you're using some kind of virtual filesystem or want to load the data from .zip files or something.
And it supports lots of common image file types including JPEG, PNG, TGA, BMP, GIF and PSD.

So I wondered if there are any downsides regarding speed.  

<!--more-->

In short: (On my machine) it's faster than libjpeg, a bit slower than libjpeg-turbo, twice as fast as lodepng (another one-file-png decoder which also has a nice API) and a bit slower than libpng. For smaller images stb_image's performance is even closer to libpng/libjpeg-turbo. GCC produces faster code than Clang. All in all I find the performance acceptable and will use stb_image more in the future (my first "victim" was <a href="https://github.com/yquake2/yquake2/commit/47cde06e27d7a81f4cc70cd287cdf47364cf69fb">Yamagi Quake II</a>).

The average times decoding a 4000x3000pixel image in milliseconds for GCC and clang with different optimization levels:

# JPEG

## libjpeg, libjpeg-turbo

I used libjpeg binaries from distributions, so compilers and optimization flags on my end didn't make a difference.

<ul>
<li>Debian Wheezy's <strong>libjpeg8</strong> 8d1-deb7u1, no turbo: 130ms</li>
<li>Ubuntu 14.04's <strong>libjpeg-turbo8</strong> 1.3.0-0ubuntu2: 69ms</li>
</ul>

## **stb_image** 2.02, using SSE intrinsics

<ul>
<li>clang -O0: 436ms</li>
<li>gcc -O0: 402ms</li>
<li>clang -O1: 179ms</li>
<li>gcc -O1: 97ms</li>
<li>clang -O2: 151ms</li>
<li>gcc -O2: 93ms</li>
<li>clang -O3: 150ms</li>
<li>gcc -O3: 85ms</li>
<li>gcc -O4: 85ms</li>
</ul>

## Results for JPEG decoding

For JPEG, if you use clang stb_image is a bit slower than libjpeg (and a lot slower than libjpeg-turbo). If you use GCC (and at least -O1), the performance is between libjpeg and libjpeg-turbo.  
Using optimization (at -O1 or more) yields significantly faster decoders than unoptimized (-O0) code (&gt;4x as fast for GCC, almost 3x as fast for clang).

This also shows that GCC seems to optimize this much better than Clang.

So stb_image has competitive performance for loading jpegs.

## *Update:* Test with a smaller image

I also did some tests with a 512x512pixel jpg image:

<ul>
<li>libjpeg-turbo: 3.21ms</li>
<li>stb clang -O0: 14.92ms</li>
<li>stb gcc -O0: 14.24ms</li>
<li>stb clang -O2: 5.19ms</li>
<li>stb gcc -O2: 3.72ms</li>
<li>stb gcc -O4: 3.33ms</li>
</ul>

libjpeg-turbo is still faster, but stb_image only takes about 16% (-O2) or 3% (-O4) longer - so it's much closer than with the big image.

# PNG

I converted the 4000x3000pixel JPEG used above to PNG with compressionlevel 9, using Gimp.
The PNG is pretty big, about 16MB.

## libpng 1.2

I used Ubuntu 14.04's <strong>libpng12</strong> (1.2.50-1ubuntu2), so again the compiler and optimization flags didn't matter.

<ul>
<li>libpng12: 293ms</li>
</ul>

## **stb_image** 2.02

<ul>
<li>clang -O0: 905ms</li>
<li>gcc -O0: 923ms</li>
<li>clang -O1: 455ms</li>
<li>gcc -O1: 457ms</li>
<li>clang -O2: 432ms</li>
<li>gcc -O2: 408ms</li>
<li>clang -O3: 424ms</li>
<li>gcc -O3: 394ms</li>
<li>gcc -O4: 393ms</li>
</ul>

## **lodepng** version 20150321

<ul>
<li>clang -O0: 1902ms</li>
<li>gcc -O0: 1862ms</li>
<li>clang -O1: 862ms</li>
<li>gcc -O1: 814ms</li>
<li>clang -O2: 698ms</li>
<li>gcc -O2: 680ms</li>
<li>clang -O3: 676ms</li>
<li>gcc -O3: 587ms</li>
<li>gcc -O4: 581ms</li>
</ul>

## Results for PNG decoding:

<ul>
<li>stb_image is a lot faster than lodepng, with and without compiler optimization.</li>
<li>gcc produces faster code than clang, but the difference is smaller than in the JPEG case</li>
<li>stb_image/lodepng decoders built with with <em>-O1</em> are more than twice as fast as ones built without optimization (<em>-O0</em>)</li>
<li>libpng is fastest, optimized stb_image takes about 33-40% longer, optimized lodepng takes about 100-130% longer</li>
<li><em>See below:</em> For smaller images stb_image's performance is much closer to libpng.</li>
</ul>

So, I think stb_image's png decoding speed is still acceptable.. however png in general is kinda slow and should probably not be used for games if you have lots of (big) textures.  
If you have the same picture as JPG and PNG (as I had in my tests), decoding from JPG (with stb_image) is more than 4x as fast as decoding from PNG (also stb_image; similar for libjpeg-turbo vs libpng).

If loading performance is important to you (you load that many textures that it really slows you down),
you should consider using DDS or a similar format that can be directly uploaded to the GPU.
(DDS can be used with and without alpha channel).  
Rich Geldreich's Crunch might be of interest: https://code.google.com/p/crunch/  

Also note that if you load your game data from .zip files (like Doom3 .pk4)
or another compressed archive format, compressed image files (like PNG or JPEG)
loaded from such an archive will be decompressed twice: Once when loading from
the .zip (or whatever) and then when decoding the image (i.e. what is benchmarked here).  
This makes loading it more expensive without making the files smaller: Already
compressed data usually doesn't get any smaller when compressing it again.  
There are two ways to prevent "paying twice" here:  

1. Add them to the archive uncompressed (at least zip allows you to just store
   files without further compression with `-0`),
   so loading them from the archive will be fast  
   (=> no decompress when loading from archive, only when decoding image)
2. You can create PNGs that are not compressed (usually by setting compression
   level to `0`. With `pngcrush` you could use `pngcrush -force -l 0 in.png out.png`)  
   Then the archiver can compress them with its own compression algorithm,
   which might even be better than the one used by PNG (deflate, same as zip uses)  
   (=> decompressed when loading from archive, but not when decoding image)

Anyway, if PNGs work for you, using stb_image instead of libpng is feasible and might simplify both your code and your build process.

## *Update:* Test with smaller images

I did some additional tests with a 512x512pixel png that has an alpha-channel, which is probably closer to game development requirements. Because it's much faster to decode this, I ran 300 decode iterations instead of 100.  
Furthermore, I only tested this with -O0 and -O2, which should be most relevant in practice (for debug and release builds).

<ul>
<li>libpng: 6.07ms</li>
<li>stb gcc -O0: 19.17ms</li>
<li>stb clang -O0: 19.96ms</li>
<li>stb gcc -O2: 6.53ms</li>
<li>stb clang -O2: 7.00ms</li>
<li>stb gcc -O4: 6.22ms</li>
<li>lodepng gcc -O0: 31.25ms</li>
<li>lodepng gcc -O2: 10.81ms</li>
</ul>

So while for the huge 24bit RGB png stb_image took about 33-40% longer to decode than libpng, for the small 32bit RGBA png it was <em>less than 10% longer</em> (in the optimized cases).

And some more for a 512x512 RGB picture <em>without</em> alpha-channel:

<ul>
<li>libpng: 5.00ms</li>
<li>stb gcc -O2: 4.99ms</li>
<li>stb gcc -O4: 4.69ms</li>
</ul>

In this case stb_image even is a bit faster than libpng!

# How I tested:

I wrote a hacky test-program that loads an image file into a buffer and then measures how long it takes to decode that buffer 100 times with the tested codec and divided the result by 100, see <a href="https://gist.github.com/DanielGibson/e0828acfc90f619198cb">imgLoadBench.c</a>  
I ran that 3 times in a row and used the best result.

I used a random 4000x3000pixel JPG (about 2.6MB) image taken with a digital camera.  
For the png tests I converted it to png (about 16MB) with Gimp, using highest compression level (9).  
(I also tried compression level 1 - encoding with that is faster and the resulting file is slightly bigger, but decoding actually takes longer.)

I used <strong>clang 3.6</strong> 1:3.6.1~svn232753-1~exp1 from http://llvm.org/apt/trusty/ llvm-toolchain-trusty-3.6/main and Ubuntu 14.04's <strong>gcc 4.8</strong> 4.8.2-19ubuntu1.  
Tests were executed on a Intel Haswell i7-4771 system running Linux Mint 17.1 x86_64 with Kernel 3.16.0-29-lowlatency #39-Ubuntu SMP PREEMPT.

Yeah, all this is not highly scientific, but should give a rough idea of the performance of stb_image and lodepng compared to the "normal" libjpeg, libjpeg-turbo and libpng.

stb\_image: <a href="//github.com/nothings/stb">Sean Barrett's stb_ libs on Github</a>  
lodepng: <a href="http://lodev.org/lodepng/">Lode Vandevenne's LodePNG</a>  
libjpeg-turbo: <a href="http://www.libjpeg-turbo.org/">Project Homepage</a>  
libpng: <a href="http://www.libpng.org/pub/png/libpng.html">Project Homepage</a>  
RBDoom3BFG: <a href="https://github.com/RobertBeckebans/RBDOOM-3-BFG/">I stole the code to use libpng and libjpeg for comparison there</a>

imgLoadBench.c: <a href="https://gist.github.com/DanielGibson/e0828acfc90f619198cb">My crappy test program</a>

