{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Test.Tasty.Iverilog where

import           Data.Coerce               (coerce)
import qualified Data.Text                 as T
import           System.Directory          (listDirectory)
import           System.FilePath           ((</>))
import           System.FilePath.Glob      (glob)

import           Test.Tasty.Common
import           Test.Tasty.Program
import           Test.Tasty.Providers

-- | Make executable from Verilog produced by Clash using Icarus Verilog.
--
-- For example, for I2C it would execute:
--
-- @
-- iverilog \
--   -I test_i2c -I test_bitmaster -I test_bytemaster \
--   -g2 -s test_i2c -o test_i2c.exe \
--   <verilog_files>
-- @
--
data IVerilogMakeTest = IVerilogMakeTest
  { ivmSourceDirectory :: IO FilePath
    -- ^ Directory containing VHDL files produced by Clash
  , ivmTop :: String
    -- ^ Entry point to be compiled
  }

instance IsTest IVerilogMakeTest where
  run optionSet IVerilogMakeTest{ivmSourceDirectory,ivmTop} progressCallback = do
    src <- ivmSourceDirectory
    libs <- listDirectory src
    verilogFiles <- glob (src </> "*" </> "*.v")
    runIcarus src (mkArgs libs verilogFiles ivmTop)
   where
    mkArgs libs files top =
         concat [["-I", l] | l <- libs]
      <> ["-g2", "-s", top, "-o", top <> ".exe"]
      <> files

    icarus workDir args = TestProgram "iverilog" args NoGlob PrintNeither False (Just workDir)
    runIcarus workDir args = run optionSet (icarus workDir args) progressCallback

  testOptions = coerce (testOptions @TestProgram)

-- | Run executable produced by 'IverilogMakeTest'.
--
-- For example, for I2C it would execute:
--
-- @
-- vvp test_i2c.exe
-- @
--
data IVerilogSimTest = IVerilogSimTest
  { ivsExpectFailure :: Maybe (TestExitCode, T.Text)
    -- ^ Expected failure code and output (if any)
  , ivsStdoutNonEmptyFail :: Bool
    -- ^ Whether a non-empty stdout means failure
  , ivsSourceDirectory :: IO FilePath
    -- ^ Directory containing executables produced by 'IVerilogMakeTest'
  , ivsTop :: String
    -- ^ Entry point to simulate
  }

instance IsTest IVerilogSimTest where
  run optionSet IVerilogSimTest{..} progressCallback = do
    src <- ivsSourceDirectory

    copyDataFilesHack src src

    let topExe = ivsTop <> ".exe"
    case ivsExpectFailure of
      Nothing -> run optionSet (vvp src [topExe]) progressCallback
      Just exit -> run optionSet (failingVvp src [topExe] exit) progressCallback
   where
    vvp workDir args =
      TestProgram "vvp" args NoGlob PrintNeither ivsStdoutNonEmptyFail (Just workDir)

    failingVvp workDir args (testExit, expectedErr) =
      TestFailingProgram
        (testExitCode testExit) "vvp" args NoGlob PrintNeither False
        (specificExitCode testExit) (ExpectEither expectedErr) (Just workDir)

  testOptions = coerce (testOptions @TestProgram)
