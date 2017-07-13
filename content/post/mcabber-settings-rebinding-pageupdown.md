+++
date = "2009-10-01T22:34:06+00:00"
draft = false
title = "MCabber - Settings and rebinding of PageUp/PageDown"
tags = [ "Linux", "mcabber", "xterm title" ]
+++


After years of using centericq for ICQ and Jabber I switched to gajim (ICQ via transport), because centericq didn't have any useable UTF8 support. I was never really satisfied with gajim though, because I happen to switch between my PC and my Notebook multiple times a day, resulting in inconsistent chat-histories etc - a console based solution in a <a href="http://www.gnu.org/software/screen/screen.html">screen</a> is so much nicer.

So I tried <a href="http://www.mcabber.com">MCabber</a>, that turned out to be really great once you've configured it to your needs. After installing MCabber (most Linux/BSD distributions should have a package or port) you'll want to configure it to your needs.
<!--more-->

Create a <code>.mcabber/</code> directory in your home-dir, with subdirs <code>histo/</code> and <code>otr/</code>. Those directories should be only accessible by yourself (chmod 700) or MCabber will print out a warning at startup.

You'll also need to put a <code>mcabberrc</code> file into <code>~/.mcabber/</code>, <a href="http://mcabber.com/files/mcabberrc.example">the one that comes with mcabber</a> (debian users will find it at /usr/share/doc/mcabber/examples/) is a good start and documented.

<code>mcabberrc</code> should have chmod 600.

I enhanced it a bit to suit my needs:
<ul>
	<li>If you have a lot of contacts, a quick search function may come in handy. Usually its "/roster search somename". I prefer just "/rs somename" so add <code>alias rs = roster search</code> to your mcabberrc.</li>
	<li>Sometimes I want to scroll up the history - and don't want it to scroll down if my buddy sends me a message. You can use "/buffer scroll_lock" and "/buffer scroll_unlock" or just "/buffer scroll_toggle" to achieve that. Just bind the toggling to F6, so you can enable and disable scroll lock with F6: Put <code>bind 270 = buffer scroll_toggle</code> in your mcabberrc.</li>
</ul>
<strong>Note:</strong> Why "270"? 270 is the curses-keycode of F6. At least on my box. On other systems or with other versions of the curses library (which mcabber uses) the keycode may be different.  Fortunately MCabber helps you to find out the keycode: just press an (unbound) key in MCabber and something like <code>[21:26:16] Unknown key=270</code> will appear in mcabbers log window.

MCabbers way of sending multi line messages is a bit unusual: First you have to start multiline mode ("/msay begin" or "/msay toggle"), then you write your message (just hit return once you've finished one line) and, when you're done you send the message ("/msay send" or Ctrl-d).
<ul>
	<li>I want to start multiline-mode with Alt-Enter (keycode M13 on my system), so I add the following binding: <code>bind M13 = msay toggle</code></li>
</ul>
Now you should have a fairly useable config.

But there was one thing still that annoyed me: Going through the roster (contact list) is bound to PageUp/PageDown - and this is done in MCabbers code, not in the mcabberrc. My problem was, that the PageUp/Down-keys are next to the Enter-key on my Notebook. If I missed the enter key and pressed both PageUp/Down and Enter, the message would be sent to the next/previous contact in my roaster.. that sucks.

I decided to make PageUp/Down scroll the chat history and use Ctrl-PageUp/Down to move within the roster. To do that I need the keycodes of Ctrl-PageUp/Down (easy, because there is no hardcoded binding on them: MK3 and MK4 on my system) and of PageUp/Down - not easy, because MCabber doesn't show the keycodes of bound keys.

<em>The Solution:</em> The curses keycodes are defined in <code>/usr/include/curses.h</code> - look for KEY_NPAGE and KEY_PPAGE. If you can't find curses.h, you probably haven't installed the curses development package (on debian it's called libncurses5-dev).

You'll get octal values (like 0522 and 0523 in my case) that need to be translated to decimal values to get a keycode for MCabber:

PageDown: <code>#define KEY_NPAGE  0522</code> 0522 is an octal value, convert to decimal (right to left): <strong>2</strong>*8^0+<strong>2</strong>*8^1+<strong>5</strong>*8^2 = 2*1+2*8+5*64 = 338

PageUp is KEY_PPAGE, defined as 0523 (on my system), which translates to 339. Add the following to your mcabberrc to change the semantics of PageUp/Down and Ctrl-PageUp/Down:

```text
# Ctrl-PGUP/DN -> move in contact list
bind MK3 = roster up
bind MK4 = roster down
# PGUP/DN -> scroll in message history
bind 339 = buffer up
bind 338 = buffer down
```

Last but not least: I find it convenient to have a sensible window-title in the terminal running MCabber (in screen). Most common terminal emulators (xterm, urxvt, Gnome Terminal, xfce terminal, ...) can handle the xterm escape sequence to set the title (see <a href="http://tldp.org/HOWTO/Xterm-Title.html">this page</a> for more information).

So I created a simple shellscript <code>settitle.sh</code> to execute before starting mcabber, like this:

<code>$ settitle.sh "MCabber" &amp;&amp; mcabber</code>

<strong>settitle.sh</strong> looks like this:

```bash
#!/bin/sh
printf '33]2;%s07' $1
```
