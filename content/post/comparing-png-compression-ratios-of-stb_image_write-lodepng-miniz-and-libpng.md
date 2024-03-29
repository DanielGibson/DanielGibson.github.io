+++
date = "2015-07-18T02:29:24"
title = "Comparing png compression ratios of stb_image_write, LodePNG, miniz and libpng"
tags = [ "C", "compression", "libpng", "lodepng", "miniz", "png", "stb", "stb_image_write" ]
ghcommentid = 11
+++

Because of https://github.com/nothings/stb/issues/113 I was wondering how good/bad
stb_image_write's PNG compression really is in comparison to other encoders.

So I did a quick comparison between stb_image_write (v0.98) LodePNG (version 20150418),
miniz's `tdefl_write_image_to_png_file_in_memory_ex()` (v1.15) and libpng (version 1.2.50
from Ubuntu 14.04), always with the highest possible compression I could configure.

<!--more-->

I used four different test images, all 24bit RGB:  
A screenshot from <a href="https://github.com/yquake2/zaero">Quake2: Zaero</a> in 1680x1050,
a screenshot from <a href="https://github.com/RobertBeckebans/RBDOOM-3-BFG/">RBDoom3BFG</a> in 1392x920,
the classic "<a href="https://en.wikipedia.org/wiki/Lenna">Lenna</a>" test image in 512x512
and a <a href="http://wallpapercave.com/w/a5QVpjx">colorful wallpaper with several parrots</a> in 2560x1600.  
*Update:* I also tested a screenshot of <a href="http://snakebird.noumenongames.com/">Snakebird</a>

# Results:

I tested libpng with highest compression (`png_set_compression_level(png_ptr, 9);`) and default compression.  
libpng with highest compression is used as 100%, as it almost always yields the smallest image.

**_UPDATE:_** `stb_image_write.h` now lets you set your own deflate-implementation for compressing PNG,
via `#define STBIW_ZLIB_COMPRESS my_stbiw_zlib_compress`,
see [stb_image_write.h](https://github.com/nothings/stb/blob/master/stb_image_write.h) for details.  
If you make it use the deflate implementations of zlib (`compress2()`) or miniz (`mz_compress2()`);
the resulting file sizes will be much closer to libpng, as you can see the results of
stb_image_write.h with miniz's `mz_compress2()` (compression level 9) in the "stb+miniz" rows.

## Doom3BFG Screenshot:

Encoder        | Bytes   | Percent
---------------|---------|--------
libpng high    | 1133340 | 100%
libpng default | 1167675 | 103%
LodePNG        | 1198051 | 106%
miniz          | 1569473 | 138%
stb            | 1608577 | 142%
stb+miniz      | 1163202 | 103%

## Quake2 Screenshot:

Encoder        | Bytes   | Percent
---------------|---------|--------
libpng high    | 2082772 | 100%
libpng default | 2125051 | 102%
LodePNG        | 2243547 | 108%
miniz          | 2683565 | 129%
stb            | 3146951 | 151%
stb+miniz      | 2166861 | 104%

## Parrots:

Encoder        | Bytes   | Percent
---------------|---------|--------
libpng high    | 5062358 | 100%
libpng default | 5195689 | 103%
LodePNG        | 5328474 | 105%
miniz          | 9000478 | 178%
stb            | 7439122 | 147%
stb+miniz      | 5233623 | 103%

## Lenna:

Encoder        | Bytes  | Percent
---------------|--------|--------
libpng high    | 476195 | 100%
libpng default | 476196 | 100%
LodePNG        | 499061 | 105%
miniz          | 729880 | 153%
stb            | 723394 | 152%
stb+miniz      | 514857 | 108%

## Snakebird:

Encoder        | Bytes  | Percent
---------------|--------|--------
libpng high    | 259338 | 100%
libpng default | 265571 | 102%
LodePNG        | 291126 | 112%
miniz          | 226136 | 87%
stb            | 315422 | 122%
stb+miniz      | 263418 | 102%

# Conclusion

Sean was right with "It looks to me like the miniz doesn't use PNG filters, 
so it's just compressing the raw image data as is, which isn't going to be
very good compression either, but along a different axis.".  
Sometimes the compression of miniz (or more correctly `tdefl_write_image_to_png_file_in_memory_ex()`)
is better and sometimes `stbi_write_png()` is better - so it doesn't matter 
which one you use, if you wanna use one of them.

However, compared to libpng and LodePNG both don't compress very well - 
the resulting images are 29%-78% bigger *(When combining them it gets a lot better, see below)*.  
LodePNG on the other hand produces almost as good results as libpng (only 5%-8% bigger)
and is significantly easier to use - integrating it in your project is easy
(just drop the source and the header file to your project) and using it 
is about as easy as stbi_write_png().  
(For image loading however I found stb_image much better than LodePNG,
as it loads PNGs faster, see
[my other blogpost](/2015/03/23/comparing-performance-stb_image-vs-libjpeg-turbo-libpng-and-lodepng/).

*UPDATE:* A kinda strange case is the Snakebird-Screenshot: Sean said that
["something more computer-arty -- flat colors or gradients"](https://twitter.com/nothings/status/622310841564577797)
will yield different results, because
["that's one of the places where the PNG filters are beneficial"](https://twitter.com/nothings/status/622310939426078720).  
And he was right: In that case the `stbi_write_png()` output was only 22% bigger
than the libpng output - but for some reason miniz, which does not seem to
do PNG filtering, compressed even better than libpng (the resulting file was 13% smaller).

**UPDATE:** When making stb_image_write use the deflate implementation of miniz
(instead of its own), it produces PNGs that are usually only about 2-4% bigger than
what libpng produces (see the "stb+miniz" rows above).
Especially if you're using zlib or miniz in your project anyway, doing this should
be a nobrainer as it's super simple, as this example for miniz shows:

```c
static unsigned char*
my_stbi_zlib_compress( unsigned char *data, int data_len,
                       int *out_len, int quality )
{
  mz_ulong buflen = mz_compressBound(data_len);
  // Note that the returned buffer will be free'd by stbi_write_png*()
  // with STBIW_FREE(), so if you have overridden that (+ STBIW_MALLOC()),
  // adjust the next malloc() call accordingly:
  unsigned char* buf = malloc(buflen);
  if( buf == NULL
      || mz_compress2(buf, &buflen, data, data_len, quality) != 0 )
  {
      free(buf); // .. yes, this would have to be adjusted as well.
      return NULL;
  }
  *out_len = buflen;
  return buf;
}

#define STBIW_ZLIB_COMPRESS  my_stbi_zlib_compress
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

// use the stbiw_* functions as usual; by setting
// stbi_write_png_compression_level = 9; you can change the deflate
// compression level (named "quality" above)
```

(For zlib it's basically the same, only the functions don't have the `mz_` prefix.)

## The Code:

Can be found at: https://gist.github.com/DanielGibson/eb322f8054c2dfef06a9

Needs:

 *  stb_image.h and stb_image_write.h from https://github.com/nothings/stb
 *  lodepng.c and lodepng.h from http://lodev.org/lodepng/
 *  miniz.c from https://github.com/richgel999/miniz
 *  libpng from http://libpng.org/ or your Linux distro or whatever (tested v1.2.50)

## For Reference: The images

(click for full size)

[![Doom 3 BFG](/images/d3bfg_libpng-small.png)](/images/d3bfg_libpng.png)

[![Quake 2: Zaero](/images/q2_libpng-small.png)](/images/q2_libpng.png)

[![Snakebird](/images/snakebird2_libpng-small.png)](/images/snakebird2_libpng.png)

[Lenna](https://en.wikipedia.org/wiki/Lenna)

And a wallpaper of parrots, available at:
http://wallpapercave.com/w/a5QVpjx 

