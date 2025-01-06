# wlfm -- A Small Warlords File Manager
## About
This is a file manager, that allows to transfer physical [Warlords](https://en.wikipedia.org/wiki/Warlords_(video_game_series)) saved games to a manager file and vice versa. Main goal is finding a solution for the fact, that the game by design only allows for up to 8 saved games, each having max. 15 characters as a description. Both limitations are not very comfortable and also leave out aspects like a time stamp of the last change.

I wanted something to overcome that. Sometimes you just want to stache away your saves, maybe continuing a match later, while freeing up slots for more immedate use. Maybe you just want to archive a save with an easy means of getting it back into the game but also need a proper description what that save was all about. This is what the project tries to tackle.

## Features
Here are some key aspects about it:

* The tool is supposed to work on the same machine as Warlords itself can run on. As such it works with EGA graphics cards under _MS DOS_.
* The memory requirements might be higher than for _Warlords_ itself. I haven't tested the limits of that. CPU load on the other hand should not be a big deal.
* The manager can store up to 128 saved game files, which roughly adds up to 8 MB in total, if the manager is filled entirely.
* Each saved game slot stores information on when it was added to the manager, a 46 characters long description entered by the user, as well as the file size and an (internal) check sum for integrity checks. This gives a better overview of contents.
* When transferring saved games back and forth, each saved game is taken as-is, meaning the initially entered 15 character description from Warlords is not altered. So restoring a saved game from the manager to the game restores it exactly the same way as it was before, except for maybe ending up in a different slot than before. Each stored save can be saved to any of the eight slots or _Warlords_.
* If you exchange saves with someone else, transferring the saved game stache of the file manager is more convenient, as you have all the files you want to send in one place/file.
## The Particular Setting
This project basically started out as a fun project and as such is not to be taken too seriously. I wanted to see how far I'd come, creating the tool in its »native« environment, an _MS DOS_ based machine from around the time _Warlords_ was released (1990). This meant for me: Working strictly on a genuine 486 PC, editing the code under _Windows 95_ (mostly for convenience reasons) and compiling for DOS. My tools used for creating it are as follows:
* **DOS version** of [_FreeBasic_](https://freebasic.net/) version 1.08.1, running on a genuine
* _Windows 95_ version 4.00.950 B. Source code editor used is
* _Notepad++_ version 3.9 (last one still working on _Windows 95_).

The particular version 1.08.1 of the _FreeBasic_ compiler does not use up too much RAM on my machine (which is some whopping 32 MB!) and works just fine. Newer versions should also work in general, but did not fly on my particular computer for running out of memory. So I left it at working with the relatively outdated FBC.

Getting _Notepad++_ version 3.9 was quite an endeavour. It's also once again a nice instance of »don't trust AI«, because of course I also asked ChatGPT what version was the last one working on _Windows 95_ and of course the answer was bullshit. After finding a nice place with older installers for _Notepad++_ (which is a challenge in itself) I messed around with finding out which version was indeed the last working one. But it was worth the effort. I still had to adapted the VB-definitions to my needs, so that syntax highlighting worked properly (version 3.9 does not yet allow for adding your own defintions in an easy fashion...). But in the end it works rather well.

So the _WLFM_ (_Warlords File Manager_) was created strictly on that old PC. The source you find here in this repo is 1:1 the same as was written on the old box.

## Usage
The tool is actually quite straight-forward to use. Place it in the folder of your _Warlords_ installation and run it. If you are working under _Windows_ 9x, it will work just fine out of the box. If you work with pure MS DOS, you might need a DOS extender. For convenience reasons there is one included here, (the [_CWSDPMI_](http://sandmann.dotster.com/cwsdpmi/)). Run it, before you start the manager, and everything should be fine.

**Note**: As current _Windows_ versions do not include the 16 bit subsystem any longer, the _wlfm.exe_ file will most likely not work on your modern Windows. Go back to a 32 bit Windows, if you want to use it there. Or use [_DOSBox_](https://www.dosbox.com/). For a genuine experience I'd recommend using this on an actual 386, 486, Pentium I or Pentium II PC. =) The contents of the manager are stored in file _wars.sav_. So if you want to transfer or backup all your saves at once, this is your file.
## Compiling
If you want to compile the binary yourself, you need at least FreeBasic 1.08 to get it to compile. There is already the batch file _make.bat_ included, that does the compiling. If you have set your _%PATH%_ variable to include the FBC compiler, you can run it from the folder with the source file _wlfm.bas_. On a genuine 386 or 486 machine it will take a few seconds to complete. You can also place _wlfm.bas_ and _make.bat_ in the compiler folder, where the _fbc.exe_ file is located, and run the batch file from there. The resulting _wlfm.exe_ will work just fine.
## Disclaimer
For all the legal mumbo jumbo such as warranty or copyright claims, read the _LICENSE_ file. Part of the files you find in this repo is also the _CWSDPMI r7_, in form of file _CWSDPMI.EXE_. This is not part of this project but the work of [C.W. Sandmann](http://sandmann.dotster.com/cwsdpmi/). It is just here for convenience reasons.

The pre-compiled binary _wlfm.exe_ is the product of the also handed _wlfm.bas_ file. If you are not satisfied with that assurance, look at section [Compiling](#compiling).