#!/bin/bash
HPVER=7.10.3
HPARCH=x86_64
export WINEPREFIX=~/.wine-hp-$HPARCH
GHC_PATH=$WINEPREFIX/drive_c/Program\ Files/Haskell\ Platform/$HPVER/bin/ghc.exe
ARCH=win64
BUILDDIR=dist-$ARCH

sudo apt-get update
sudo apt-get install wine wget cabal-install

if [ ! -f "$GHC_PATH" ]; then
  wget -c https://www.haskell.org/platform/download/$HPVER/HaskellPlatform-$HPVER-$HPARCH-setup.exe
  wine HaskellPlatform-$HPVER-$HPARCH-setup.exe /S
fi

# https://plus.google.com/+MasahiroSakai/posts/RTXUt5MkVPt
#wine cabal update
cabal update
mkdir -p $WINEPREFIX/drive_c/users/`whoami`/Application\ Data/cabal
cp -a ~/.cabal/packages $WINEPREFIX/drive_c/users/`whoami`/Application\ Data/cabal/

wine cabal sandbox init
wine cabal install --only-dependencies --flag=BuildToyFMF --flag=BuildSamplePrograms --flag=BuildMiscPrograms
wine cabal clean --builddir=$BUILDDIR
wine cabal configure --builddir=$BUILDDIR --flag=BuildToyFMF --flag=BuildSamplePrograms --flag=BuildMiscPrograms
wine cabal build --builddir=$BUILDDIR

VER=`wine ghc -ignore-dot-ghci -e ":m + Control.Monad Distribution.Package Distribution.PackageDescription Distribution.PackageDescription.Parse Distribution.Verbosity Data.Version System.IO" -e "hSetBinaryMode stdout True" -e 'putStrLn =<< liftM (showVersion . pkgVersion . package . packageDescription) (readPackageDescription silent "toysolver.cabal")'`

PKG=toysolver-$VER-$ARCH

rm -r $PKG
mkdir $PKG
mkdir $PKG/bin
cp $BUILDDIR/build/htc/htc.exe $BUILDDIR/build/knapsack/knapsack.exe $BUILDDIR/build/nonogram/nonogram.exe $BUILDDIR/build/nqueens/nqueens.exe $BUILDDIR/build/toyconvert/toyconvert.exe $BUILDDIR/build/sudoku/sudoku.exe $BUILDDIR/build/toyfmf/toyfmf.exe $BUILDDIR/build/toysat/toysat.exe $BUILDDIR/build/toysmt/toysmt.exe $BUILDDIR/build/ToySolver/toysolver.exe $PKG/bin/
wine strip $PKG/bin/*.exe
cp -a samples $PKG/
cp COPYING-GPL README.md CHANGELOG.markdown $PKG/
zip -r $PKG.zip $PKG
