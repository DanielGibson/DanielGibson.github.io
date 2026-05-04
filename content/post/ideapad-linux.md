+++
date = "2026-06-03T01:30:10+02:00"
title = "Running Linux on an AMD Zen3-based Lenovo IdeaPad Slim 3"
slug = "ideapad-linux"
tags = [ "Linux", "ACPI", "Lenovo", "IdeaPad", "keyboard", "bug", "suspend", "s2idle" ]
draft = false
toc = true
ghcommentid = 16
+++

I had a simple task: Install and configure my mothers new laptop.  
To my surprise she wanted to to try Linux, because Windows 11 again has a new UI and her reasoning
was that if she needs to get used to something new it might as well be Linux - and I guess the fact
that Win11 only got buggier over time has reached normies now.

Now this *should* be no problem.

Unfortunately that laptop, a Lenovo IdeaPad Slim 3 16ABR8, turned out to have firmware bugs related
to suspend (s2idle).

I debugged the issues and eventually found ways to fix/work around them - this blogpost shows how.

<!--more-->

# The Problems

After suspend+resume (**s2idle** standby) the **keyboard stopped working**. Several sources suggested
setting a kernel parameter (`i8042.nopnp`), which made the keyboard *mostly* work after resume,
except the **Fn keys/multimedia keys didn't**.  
For example, pressing the `F1`/`Mute` key only registered as `F1`, even when pressed together
with `Fn`, same for all other `Fn` combinations.

The **lid switch also stopped working** after the first suspend+resume, so when closing the laptop
it didn't go to sleep or at lock the screen or whatever was configured - here I didn't find any
kernel parameter that helped.

At least those problems were undone by rebooting... until the next suspend.

A minor issue was an **ACPI error** that happened on resume - though of course at the time I didn't
know whether it's minor or the root of the problems.

```
ACPI: \_SB_.PEP_: Successfully transitioned to state lps0 exit
ACPI: \_SB_.PEP_: Successfully transitioned to state lps0 ms exit
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PC00.LPCB.EC0.SNTM],
	AE_NOT_FOUND (20251212/psargs-332)

No Local Variables are initialized for Method [_DSM]

Initialized Arguments for Method [_DSM]:  (4 arguments defined for method
	invocation)
  Arg0:   000000002ff511a6 <Obj>           Buffer(16) 56 0D E0 11 64 CE CE 47
  Arg1:   000000005176ebd5 <Obj>           Integer 0000000000000000
  Arg2:   00000000e877e9f8 <Obj>           Integer 0000000000000004
  Arg3:   0000000024f78b95 <Obj>           Package 0000000024f78b95

ACPI Error: Aborting method \_SB.PEP._DSM due to previous error (AE_NOT_FOUND)
	(20251212/psparse-529)
ACPI: \_SB_.PEP_: Failed to transitioned to state screen on
```


# Solutions

## Avoid breaking the keyboard and lid switch with suspend

It turned out that the laptops EC (embedded controller) [needs a little me-time before suspend](https://bugzilla.kernel.org/show_bug.cgi?id=221383#c27),
or it becomes uncooperative after waking up[^fn:me-time] and doesn't deliver keyboard and lid switch
events anymore - this most probably is a firmware bug[^fn:fw-bug].

I have a patch that adds a 2.5 second sleep right before suspend at the appropriate place in the
**amd_pmc** kernel module, which will [hopefully be merged](https://lore.kernel.org/platform-driver-x86/20260512202645.1549111-1-daniel@gibson.sh/t/#u)
in the Linux kernel.

Until it has been merged (and that kernel version ends up in your Linux distribution), you can use
my out-of-tree version of the module that contains the patches and should work with Kernel 6.5 and
newer. You can find it and installation instructions at https://github.com/DanielGibson/amd_pmc-ideapad,
if it works for you I recommend installing it with DKMS so it gets automatically built and installed
when your distro ships a kernel update.

If your device isn't already detected automatically as affected by this issue, the updated **amd_pmc**
kernel module has a parameter `delay_suspend` that allows explicitly enabling (or disabling) it;
the aforementioned Github project has more information on this.

### Possibly remaining problems (with wakealarm)

Unfortunately, this does not *completely* fix the issues on *all* devices.

Normal suspend and resume (with keyboard or lid switch or touchpad, ...) works
fine, but timer-base suspend+resume[^fn:wakealarm] still has the old problems on some machines (like my 16ABR8),
but apparently works fine on others (like [14ARP10](https://bugzilla.kernel.org/show_bug.cgi?id=221383#c66)).

I think this shouldn't be a big problem in practice, but you should probably be
aware of this.

At least on 16ABR8 you can still use the `i8042.nopnp` kernel commandline parameter[^fn:cmdparm]
to keep *most* of the keyboard functional after a timed suspend. That will allow
you to unlock your screensaver after resume, save your open files and then reboot
to restore full keyboard and lid switch functionality.

## Workaround for the ACPI `AE_NOT_FOUND` problem

The aforementioned ACPI error (`Could not resolve symbol [\_SB.PC00.LPCB.EC0.SNTM], AE_NOT_FOUND`)
turned out to be unrelated to the keyboard/lid problems and I haven't found any other issues
caused by it.

It's still ugly and there's a reasonably easy way to fix it which I'd like to describe, if only
to allow others having similar issues to find it.

> **NOTE:** While the keyboard issue seems to affect lots of IdeaPads with Zen3 ("Barcelo") and
> Zen3+ ("Rembrandt") CPUs, this ACPI error seems to be more specific to the *IdeaPad Slim 3 16ABR8*
> and probably other \*ABR8 devices[^fn:modelname], at least with the current BIOS version (KYCN41WW).  
> Don't blindly apply my fix, check first if you have this exact error (about `\_SB.PC00.LPCB.EC0.SNTM`)
> in dmesg after suspend!
>
> Maye you have similar `AE_NOT_FOUND` errors for other symbols, in which case my fix may at least
> show a way to work around them, but you'll have to adapt it.

So the complaint is that the method `\_SB.PC00.LPCB.EC0.SNTM` can't be found, because it doesn't
exist. Most probably it should've been `\_SB.PCI0.LPC0.EC0.SNTM`, a method from dsdt.dsl that is
otherwise unused. `PCI0`, `LPC0` and `EC0` are all (nested) devices.

Thankfully it's possible to create ACPI fake devices (or ACPI dummy devices or ACPI stub
devices[^fn:fake-dev]), they're called **"Module Device"** there and at least when they do *not*
contain a `_CRS` object or method they're *"simple container objects"*[^fn:module-dev-link].

So one can just create fake devices `PC00` and `LPCB` and `EC0` and a `SNTM` method in them
which calls the actual method.  
Alternatively I guess the method could remain empty to do nothing, which would still make the
ACPI error go away so the ACPI method calling the nonexisting method can finish.

It looks like this:

```c
// create stub/fake/dummy devices and a stub method for the
// method missing in the BIOS ACPI tables (\_SB.PC00.LPCB.EC0.SNTM)
// and make it call the proper method (\_SB.PCI0.LPC0.EC0.SNTM)
DefinitionBlock ("", "SSDT", 2, "LENOVO", "SNTMFIX", 0x00000001)
{
	// the actually existing method from dsdt.dsl
	External (_SB.PCI0.LPC0.EC0.SNTM, MethodObj) // 0 Arguments

	Scope (\_SB)
	{
		Device (PC00)
		{
			// https://uefi.org/specs/ACPI/6.6/09_ACPI_Defined_Devices_and_Device_Specific_Objects.html#module-device
			// says that devices with HID "ACPI0004" are "module devices"
			// that act as simple containers if they contain no _CRS object
			Name (_HID, "ACPI0004" /* Module Device */)  // _HID: Hardware ID
			Device (LPCB)
			{
				Name (_HID, "ACPI0004" /* Module Device */)
				Device (EC0)
				{
					Name (_HID, "ACPI0004" /* Module Device */)
					Method (SNTM, 0, NotSerialized)
					{
						// call real method from dsdt.dsl
						\_SB.PCI0.LPC0.EC0.SNTM ()
					}
				}
			}
		}
	}
}
```

Save this as `sntmfix.dsl` and use `iasl`[^fn:iasl] to compile it (`iasl sntmfix.dsl`).

If you're using the **grub** bootloader, copy the resulting `sntmfix.aml` to `/boot/` and tell
grub to load it on boot by editing `/etc/grub.d/40_custom` (or another file that ends up in the
generated `/boot/grub/grub.cfg`, or edit that file directly if you don't generate it) and adding
the following line:  
`acpi /boot/sntmfix.aml`  
*(if `/boot/` has its own partition on your system it should be just `acpi /sntmfix.aml`)*

Afterwards run `# update-grub` or, if that doesn't exist, `# grub-mkconfig -o /boot/grub/grub.cfg`.

If you're not using grub, see the [Arch Wiki](https://wiki.archlinux.org/title/DSDT#Using_modified_code)
for instructions (yes, they should also work on other distros).

<!-- below: footnotes -->

[^fn:me-time]: relatable, to be honest

[^fn:fw-bug]: Yes, this means Lenovo could probably fix them with a BIOS update. I have little hope
    that Lenovo actually does that, as they don't officially support Linux on the affected devices,
    and I wouldn't know how to reach anyone at Lenovo who might care and has the means to have
    this fixed anyway.  
    The problem was reported in [Lenovos forums](https://forums.lenovo.com/t5/Other-Linux-Discussions/Keyboard-doesn-t-work-after-suspend-on-Linux-IdeaPad-3-15ABR8-Ryzen-7/m-p/5392909),
    and it didn't seem like they care, only other users replied, no one from Lenovo.

[^fn:wakealarm]: "wakealarm", used by `rtcwake` or the `amd-s2idle` testprogram, for example.

[^fn:cmdparm]: In `/etc/default/grub` add `i8042.nopnp`. If you already have another option in there,
    separate it with a space, like `GRUB_CMDLINE_LINUX="other_option=3 i8042.nopnp"`, if not it's
    just `GRUB_CMDLINE_LINUX="i8042.nopnp"`. Afterwards run `# update-grub`.  
    If you're not using grub, see [this ArchWiki article](https://wiki.archlinux.org/title/Kernel_parameters)
    for how to set kernel commandline options with other boot managers.

[^fn:modelname]: Though it seems like there are different devices called "IdeaPad Slim 3 16ABR8"
    on the market.. at the very least with different WiFi chips, see https://wiki.archlinux.org/title/Lenovo_IdeaPad_Slim_3_16ABR8#Wireless  
    And for other devices it's even wilder: There are different versions of the "IdeaPad Slim 3 15ARP10",
    one with "model-type" `83MM` and another with model-type `83K7` (both affected by the keyboard bug).
    And also an "Lenovo IdeaPad Slim **5** 15ARP10" (`83J3`; unclear if affected).

[^fn:fake-dev]: Hopefully this helps people who need some kind of fake device in  ACPI find this,
    because I couldn't find anything with the terms I could come up with in search engines.
    I only got to this solution because "vng3333" in the kernel bugtracker mentioned having a minimal
    SSDT with a stub and shared the code, see https://bugzilla.kernel.org/show_bug.cgi?id=221217#c5  
    There the actual method is reimplemented, I simplified it a bit by just calling it.

[^fn:module-dev-link]: https://uefi.org/specs/ACPI/6.6/09_ACPI_Defined_Devices_and_Device_Specific_Objects.html#module-device

[^fn:iasl]: The *ACPI Source Language Compiler* by Intel that can compile and disassemble ACPI tables,
    see also https://www.acpica.org  
    On Debian-based distributions like Ubuntu it's in the `acpica-tools` package.
