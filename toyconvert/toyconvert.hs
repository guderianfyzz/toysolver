{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  toyconvert
-- Copyright   :  (c) Masahiro Sakai 2012-2016
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  experimental
-- Portability :  non-portable (CPP)
--
-----------------------------------------------------------------------------

module Main where

import Data.Char
import Data.Default.Class
import Data.Maybe
import qualified Data.Version as V
import System.Environment
import System.IO
import System.Exit
import System.FilePath
import System.Console.GetOpt
import qualified Language.CNF.Parse.ParseDIMACS as DIMACS

import qualified Data.PseudoBoolean as PBFile
import qualified Data.PseudoBoolean.Attoparsec as PBFileAttoparsec

import qualified ToySolver.Data.MIP as MIP
import qualified ToySolver.Text.GCNF as GCNF
import qualified ToySolver.Text.MaxSAT as MaxSAT
import qualified ToySolver.Text.CNF as CNF
import ToySolver.Converter.ObjType
import qualified ToySolver.Converter.SAT2PB as SAT2PB
import qualified ToySolver.Converter.GCNF2MaxSAT as GCNF2MaxSAT
import qualified ToySolver.Converter.MIP2PB as MIP2PB
import qualified ToySolver.Converter.MIP2SMT as MIP2SMT
import qualified ToySolver.Converter.MaxSAT2WBO as MaxSAT2WBO
import qualified ToySolver.Converter.PB2IP as PB2IP
import qualified ToySolver.Converter.PBLinearlization as PBLinearlization
import qualified ToySolver.Converter.PB2LSP as PB2LSP
import qualified ToySolver.Converter.PB2WBO as PB2WBO
import qualified ToySolver.Converter.PBSetObj as PBSetObj
import qualified ToySolver.Converter.PB2SMP as PB2SMP
import qualified ToySolver.Converter.PB2SAT as PB2SAT
import qualified ToySolver.Converter.SAT2KSAT as SAT2KSAT
import qualified ToySolver.Converter.WBO2PB as WBO2PB
import qualified ToySolver.Converter.WBO2MaxSAT as WBO2MaxSAT
import ToySolver.Version
import ToySolver.Internal.Util (setEncodingChar8)

data Flag
  = Help
  | Version
  | Output String
  | AsMaxSAT
  | ObjType ObjType
  | IndicatorConstraint
  | SMTSetLogic String
  | SMTOptimize
  | SMTNoCheck
  | SMTNoProduceModel
  | Yices2
  | Linearlization
  | LinearlizationUsingPB
  | KSat !Int
  deriving Eq

options :: [OptDescr Flag]
options =
    [ Option ['h'] ["help"] (NoArg Help) "show help"
    , Option ['v'] ["version"] (NoArg Version)         "show version number"
    , Option ['o'] [] (ReqArg Output "FILE") "output filename"
    , Option []    ["maxsat"]  (NoArg AsMaxSAT)  "treat *.cnf file as MAX-SAT problem"
    , Option []    ["obj"] (ReqArg (ObjType . parseObjType) "STRING") "objective function for SAT/PBS: none (default), max-one, max-zero"
    , Option []    ["indicator"] (NoArg IndicatorConstraint) "use indicator constraints in output LP file"
    , Option []    ["smt-set-logic"] (ReqArg SMTSetLogic "STRING")　"output \"(set-logic STRING)\""
    , Option []    ["smt-optimize"] (NoArg SMTOptimize)   "output optimiality condition which uses quantifiers"
    , Option []    ["smt-no-check"] (NoArg SMTNoCheck)    "do not output \"(check)\""
    , Option []    ["smt-no-produce-model"] (NoArg SMTNoProduceModel) "do not output \"(set-option :produce-models true)\""    
    , Option []    ["yices2"] (NoArg Yices2) "output for yices2 rather than yices1"
    , Option []    ["linearlize"] (NoArg Linearlization) "linearliza nonlinear pseudo-boolean constraints"
    , Option []    ["linearizer-pb"] (NoArg LinearlizationUsingPB) "Use PB constraint in linearization"
    , Option []    ["ksat"] (ReqArg (KSat . read) "NUMBER") "generate k-SAT formula when outputing .cnf file"
    ]
  where
    parseObjType s =
      case map toLower s of
        "none"     -> ObjNone
        "max-one"  -> ObjMaxOne
        "max-zero" -> ObjMaxZero
        _          -> error ("unknown obj: " ++ s)

header :: String
header = unlines
  [ "Usage:"
  , "    toyconvert -o <outputfile> <inputfile>"
  , ""
  , "Supported formats:"
  , "    input: .cnf .wcnf .opb .wbo .gcnf .lp .mps"
  , "    output: .cnf .wcnf .opb .wbo .lsp .lp .mps .smp .smt2 .ys"
  , ""
  , "Options:"
  ]

data Problem
  = ProbOPB PBFile.Formula
  | ProbWBO PBFile.SoftFormula
  | ProbMIP MIP.Problem

readProblem :: [Flag] -> String -> IO Problem
readProblem o fname = do
  case map toLower (takeExtension fname) of
    ".cnf"
      | AsMaxSAT `elem` o -> readWCNF
      | otherwise -> do
          ret <- DIMACS.parseFile fname
          case ret of
            Left err  -> hPrint stderr err >> exitFailure
            Right cnf -> return $ ProbOPB $ SAT2PB.convert cnf
    ".wcnf" -> readWCNF
    ".opb"  -> do
      ret <- PBFileAttoparsec.parseOPBFile fname
      case ret of
        Left err -> hPutStrLn stderr err >> exitFailure
        Right opb -> return $ ProbOPB opb
    ".wbo"  -> do
      ret <- PBFileAttoparsec.parseWBOFile fname
      case ret of
        Left err -> hPutStrLn stderr err >> exitFailure
        Right wbo -> return $ ProbWBO wbo
    ".gcnf" -> do
      ret <- GCNF.parseFile fname
      case ret of
        Left err -> hPutStrLn stderr err >> exitFailure
        Right gcnf -> return $ ProbWBO $ MaxSAT2WBO.convert $ GCNF2MaxSAT.convert gcnf
    ".lp"   -> do
      ret <- MIP.readLPFile def fname
      case ret of
        Left err -> hPrint stderr err >> exitFailure
        Right mip -> return $ ProbMIP mip
    ".mps"  -> do
      ret <- MIP.readMPSFile def fname
      case ret of
        Left err -> hPrint stderr err >> exitFailure
        Right mip -> return $ ProbMIP mip
    ext ->
      error $ "unknown file extension: " ++ show ext
  where    
    readWCNF = do
      ret <- MaxSAT.parseFile fname
      case ret of
        Left err -> hPutStrLn stderr err >> exitFailure
        Right wcnf -> return $ ProbWBO $ MaxSAT2WBO.convert $ wcnf

transformProblem :: [Flag] -> Problem -> Problem
transformProblem o = transformObj o . transformPBLinearlization o

transformObj :: [Flag] -> Problem -> Problem
transformObj o problem =
  case problem of
    ProbOPB opb | isNothing (PBFile.pbObjectiveFunction opb) -> ProbOPB $ PBSetObj.setObj objType opb
    _ -> problem
  where
    objType = last (ObjNone : [t | ObjType t <- o])

transformPBLinearlization :: [Flag] -> Problem -> Problem
transformPBLinearlization o problem
  | Linearlization `elem` o =
      case problem of
        ProbOPB opb -> ProbOPB $ PBLinearlization.linearlize    opb (LinearlizationUsingPB `elem` o)
        ProbWBO wbo -> ProbWBO $ PBLinearlization.linearlizeWBO wbo (LinearlizationUsingPB `elem` o)
        ProbMIP mip -> ProbMIP mip
  | otherwise = problem

writeProblem :: [Flag] -> Problem -> IO ()
writeProblem o problem = do
  let mip2smtOpt =
        def
        { MIP2SMT.optSetLogic     = listToMaybe [logic | SMTSetLogic logic <- o]
        , MIP2SMT.optCheckSAT     = not (SMTNoCheck `elem` o)
        , MIP2SMT.optProduceModel = not (SMTNoProduceModel `elem` o)
        , MIP2SMT.optOptimize     = SMTOptimize `elem` o
        }
  case head ([Just fname | Output fname <- o] ++ [Nothing]) of
    Nothing -> do
      hSetBinaryMode stdout True
      hSetBuffering stdout (BlockBuffering Nothing)
      case problem of
        ProbOPB opb -> PBFile.hPutOPB stdout opb
        ProbWBO wbo -> PBFile.hPutWBO stdout wbo
        ProbMIP mip -> do
          case MIP.toLPString def mip of
            Left err -> hPutStrLn stderr ("conversion failure: " ++ err) >> exitFailure
            Right s -> hPutStr stdout s
    Just fname -> do
      let opb = case problem of
                  ProbOPB opb -> opb
                  ProbWBO wbo ->
                    case WBO2PB.convert wbo of
                      (opb, _, _)
                        | Linearlization `elem` o ->
                            -- WBO->OPB conversion may have introduced non-linearity
                            PBLinearlization.linearlize opb (LinearlizationUsingPB `elem` o)
                        | otherwise -> opb
                  ProbMIP mip ->
                    case MIP2PB.convert mip of
                      Left err -> error err
                      Right (opb, _, _) -> opb
          wbo = case problem of
                  ProbOPB opb -> PB2WBO.convert opb
                  ProbWBO wbo -> wbo
                  ProbMIP _   -> PB2WBO.convert opb
          lp  = case problem of
                  ProbOPB opb ->
                    case PB2IP.convert opb of
                      (ip, _, _) -> ip
                  ProbWBO wbo ->
                    case PB2IP.convertWBO (IndicatorConstraint `elem` o) wbo of
                      (ip, _, _) -> ip
                  ProbMIP mip -> mip
          lsp = case problem of
                  ProbOPB opb -> PB2LSP.convert opb
                  ProbWBO wbo -> PB2LSP.convertWBO wbo
                  ProbMIP _   -> PB2LSP.convert opb
      case map toLower (takeExtension fname) of
        ".opb" -> PBFile.writeOPBFile fname opb
        ".wbo" -> PBFile.writeWBOFile fname wbo
        ".cnf" ->
          case PB2SAT.convert opb of
            (cnf, _, _) ->
              case head ([Just k | KSat k <- o] ++ [Nothing]) of
                Nothing -> CNF.writeFile fname cnf
                Just k ->
                  let (cnf2, _, _) = SAT2KSAT.convert k cnf
                  in CNF.writeFile fname cnf2
        ".wcnf" ->
          case WBO2MaxSAT.convert wbo of
            (wcnf, _, _) -> MaxSAT.writeFile fname wcnf
        ".lsp" -> writeFile fname (lsp "")
        ".lp" -> MIP.writeLPFile def fname lp
        ".mps" -> MIP.writeMPSFile def fname lp
        ".smp" -> do
          writeFile fname (PB2SMP.convert False opb "")
        ".smt2" -> do
          writeFile fname (MIP2SMT.convert mip2smtOpt lp "")
        ".ys" -> do
          let lang = MIP2SMT.YICES (if Yices2 `elem` o then MIP2SMT.Yices2 else MIP2SMT.Yices1)
          writeFile fname (MIP2SMT.convert mip2smtOpt{ MIP2SMT.optLanguage = lang } lp "")
        ext -> do
          error $ "unknown file extension: " ++ show ext
          
main :: IO ()
main = do
#ifdef FORCE_CHAR8
  setEncodingChar8
#endif

  args <- getArgs
  case getOpt Permute options args of
    (o,_,[])
      | Help `elem` o    -> putStrLn (usageInfo header options)
      | Version `elem` o -> putStrLn (V.showVersion version)
    (o,[fname],[]) -> do
      prob <- readProblem o fname
      let prob2 = transformProblem o prob
      writeProblem o prob2
    (_,_,errs) -> do
      hPutStrLn stderr $ concat errs ++ usageInfo header options
      exitFailure
