%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[PatSyntax]{Abstract Haskell syntax---patterns}

\begin{code}
module HsPat (
	InPat(..),
	OutPat(..),

	irrefutablePat, irrefutablePats,
	failureFreePat, isWildPat, 
	patsAreAllCons, isConPat, 
	patsAreAllLits,	isLitPat,
	collectPatBinders, collectOutPatBinders, collectPatsBinders,
	collectSigTysFromPat, collectSigTysFromPats
    ) where

#include "HsVersions.h"


-- friends:
import HsLit		( HsLit, HsOverLit )
import HsExpr		( HsExpr )
import HsTypes		( HsType, SyntaxName )
import BasicTypes	( Fixity, Boxity, tupleParens )

-- others:
import Name		( Name )
import Var		( Id, TyVar )
import DataCon		( DataCon, dataConTyCon )
import Name		( isDataSymOcc, getOccName, NamedThing )
import Maybes		( maybeToBool )
import Outputable	
import TyCon		( maybeTyConSingleCon )
import Type		( Type )
\end{code}

Patterns come in distinct before- and after-typechecking flavo(u)rs.
\begin{code}
data InPat name
  = WildPatIn				-- wild card
  | VarPatIn	    name		-- variable
  | LitPatIn	    HsLit		-- literal
  | LazyPatIn	    (InPat name)	-- lazy pattern
  | AsPatIn	    name		-- as pattern
		    (InPat name)
  | SigPatIn	    (InPat name)
		    (HsType name)
  | ConPatIn	    name		-- constructed type
		    [InPat name]
  | ConOpPatIn	    (InPat name)
		    name
		    Fixity		-- c.f. OpApp in HsExpr
		    (InPat name)

  | NPatIn	    HsOverLit 		-- Always positive
		    (Maybe SyntaxName)	-- Just (Name of 'negate') for negative
					-- patterns, Nothing otherwise

  | NPlusKPatIn	    name		-- n+k pattern
		    HsOverLit		-- It'll always be an HsIntegral
		    SyntaxName		-- Name of '-' (see RnEnv.lookupSyntaxName)

  -- We preserve prefix negation and parenthesis for the precedence parser.

  | ParPatIn        (InPat name)	-- parenthesised pattern

  | ListPatIn	    [InPat name]	-- syntactic list
					-- must have >= 1 elements
  | PArrPatIn	    [InPat name]	-- syntactic parallel array
					-- must have >= 1 elements
  | TuplePatIn	    [InPat name] Boxity	-- tuple (boxed?)

  | RecPatIn	    name 		-- record
		    [(name, InPat name, Bool)]	-- True <=> source used punning

-- Generics
  | TypePatIn       (HsType name)       -- Type pattern for generic definitions
                                        -- e.g  f{| a+b |} = ...
                                        -- These show up only in class 
					-- declarations,
                                        -- and should be a top-level pattern

-- /Generics

data OutPat id
  = WildPat	    Type	-- wild card
  | VarPat	    id		-- variable (type is in the Id)
  | LazyPat	    (OutPat id)	-- lazy pattern
  | AsPat	    id		-- as pattern
		    (OutPat id)

  | SigPat	    (OutPat id)	-- Pattern p
		    Type	-- Type, t, of the whole pattern
		    (HsExpr id (OutPat id))
				-- Coercion function,
				-- of type t -> typeof(p)

  | ListPat		 	-- Syntactic list
		    Type	-- The type of the elements
   	    	    [OutPat id]
  | PArrPat		 	-- Syntactic parallel array
		    Type	-- The type of the elements
   	    	    [OutPat id]

  | TuplePat	    [OutPat id]	-- Tuple
		    Boxity
				-- UnitPat is TuplePat []

  | ConPat	    DataCon
		    Type    	-- the type of the pattern
		    [TyVar]	-- Existentially bound type variables
		    [id]	-- Ditto dictionaries
		    [OutPat id]

  -- ConOpPats are only used on the input side

  | RecPat	    DataCon		-- Record constructor
		    Type 	   	-- The type of the pattern
		    [TyVar]		-- Existentially bound type variables
		    [id]		-- Ditto dictionaries
		    [(Id, OutPat id, Bool)]	-- True <=> source used punning

  | LitPat	    -- Used for *non-overloaded* literal patterns:
		    -- Int#, Char#, Int, Char, String, etc.
		    HsLit
		    Type 		-- Type of pattern

  | NPat	    -- Used for literal patterns where there's an equality function to call
		    HsLit			-- The literal is retained so that
						-- the desugarer can readily identify
						-- equations with identical literal-patterns
						-- Always HsInteger, HsRat or HsString.
						-- *Unlike* NPatIn, for negative literals, the
						-- 	literal is acutally negative!
		    Type	 		-- Type of pattern, t
   	    	    (HsExpr id (OutPat id))	-- Of type t -> Bool; detects match

  | NPlusKPat	    id
		    Integer
		    Type		    	-- Type of pattern, t
   	    	    (HsExpr id (OutPat id)) 	-- Of type t -> Bool; detects match
   	    	    (HsExpr id (OutPat id)) 	-- Of type t -> t; subtracts k

  | DictPat	    -- Used when destructing Dictionaries with an explicit case
		    [id]			-- superclass dicts
		    [id]			-- methods
\end{code}

Now name in Inpat is not need to be in NAmedThing to be Outputable.
Needed by ../deSugar/Check.lhs

JJQC-2-12-97

\begin{code}
instance (Outputable name) => Outputable (InPat name) where
    ppr = pprInPat

pprInPat :: (Outputable name) => InPat name -> SDoc

pprInPat (WildPatIn)	      = char '_'
pprInPat (VarPatIn var)	      = ppr var
pprInPat (LitPatIn s)	      = ppr s
pprInPat (SigPatIn pat ty)    = ppr pat <+> dcolon <+> ppr ty
pprInPat (LazyPatIn pat)      = char '~' <> ppr pat
pprInPat (AsPatIn name pat)   = parens (hcat [ppr name, char '@', ppr pat])
pprInPat (ParPatIn pat)	      = parens (pprInPat pat)
pprInPat (ListPatIn pats)     = brackets (interpp'SP pats)
pprInPat (PArrPatIn pats)     = pabrackets (interpp'SP pats)
pprInPat (TuplePatIn pats bx) = tupleParens bx (interpp'SP pats)
pprInPat (NPlusKPatIn n k _)  = parens (hcat [ppr n, char '+', ppr k])
pprInPat (NPatIn l _)	      = ppr l

pprInPat (ConPatIn c pats)
  | null pats = ppr c
  | otherwise = hsep [ppr c, interppSP pats] -- inner ParPats supply the necessary parens.

pprInPat (ConOpPatIn pat1 op fixity pat2)
 = hsep [ppr pat1, ppr op, ppr pat2] -- ParPats put in parens

	-- ToDo: use pprSym to print op (but this involves fiddling various
	-- contexts & I'm lazy...); *PatIns are *rarely* printed anyway... (WDP)

pprInPat (RecPatIn con rpats)
  = hsep [ppr con, braces (hsep (punctuate comma (map (pp_rpat) rpats)))]
  where
    pp_rpat (v, _, True) = ppr v
    pp_rpat (v, p, _)    = hsep [ppr v, char '=', ppr p]

pprInPat (TypePatIn ty) = ptext SLIT("{|") <> ppr ty <> ptext SLIT("|}")

-- add parallel array brackets around a document
--
pabrackets   :: SDoc -> SDoc
pabrackets p  = ptext SLIT("[:") <> p <> ptext SLIT(":]")
\end{code}

\begin{code}
instance (NamedThing id, Outputable id) => Outputable (OutPat id) where
    ppr = pprOutPat
\end{code}

\begin{code}
pprOutPat (WildPat ty)	= char '_'
pprOutPat (VarPat var)	= ppr var
pprOutPat (LazyPat pat)	= hcat [char '~', ppr pat]
pprOutPat (AsPat name pat)
  = parens (hcat [ppr name, char '@', ppr pat])

pprOutPat (SigPat pat ty _)   = ppr pat <+> dcolon <+> ppr ty

pprOutPat (ConPat name ty [] [] [])
  = ppr name

-- Kludge to get infix constructors to come out right
-- when ppr'ing desugar warnings.
pprOutPat (ConPat name ty tyvars dicts pats)
  = getPprStyle $ \ sty ->
    parens      $
    case pats of
      [p1,p2] 
        | userStyle sty && isDataSymOcc (getOccName name) ->
	    hsep [ppr p1, ppr name, ppr p2]
      _ -> hsep [ppr name, interppSP tyvars, interppSP dicts, interppSP pats]

pprOutPat (ListPat ty pats)      = brackets (interpp'SP pats)
pprOutPat (PArrPat ty pats)      = pabrackets (interpp'SP pats)
pprOutPat (TuplePat pats boxity) = tupleParens boxity (interpp'SP pats)

pprOutPat (RecPat con ty tvs dicts rpats)
  = hsep [ppr con, interppSP tvs, interppSP dicts, braces (hsep (punctuate comma (map (pp_rpat) rpats)))]
  where
    pp_rpat (v, _, True) = ppr v
    pp_rpat (v, p, _)    = hsep [ppr v, char '=', ppr p]

pprOutPat (LitPat l ty) 	= ppr l	-- ToDo: print more
pprOutPat (NPat   l ty e)	= ppr l	-- ToDo: print more
pprOutPat (NPlusKPat n k ty e1 e2)		-- ToDo: print more
  = parens (hcat [ppr n, char '+', integer k])

pprOutPat (DictPat dicts methods)
 = parens (sep [ptext SLIT("{-dict-}"),
		  brackets (interpp'SP dicts),
		  brackets (interpp'SP methods)])

\end{code}

%************************************************************************
%*									*
%* predicates for checking things about pattern-lists in EquationInfo	*
%*									*
%************************************************************************
\subsection[Pat-list-predicates]{Look for interesting things in patterns}

Unlike in the Wadler chapter, where patterns are either ``variables''
or ``constructors,'' here we distinguish between:
\begin{description}
\item[unfailable:]
Patterns that cannot fail to match: variables, wildcards, and lazy
patterns.

These are the irrefutable patterns; the two other categories
are refutable patterns.

\item[constructor:]
A non-literal constructor pattern (see next category).

\item[literal patterns:]
At least the numeric ones may be overloaded.
\end{description}

A pattern is in {\em exactly one} of the above three categories; `as'
patterns are treated specially, of course.

The 1.3 report defines what ``irrefutable'' and ``failure-free'' patterns are.
\begin{code}
irrefutablePats :: [OutPat id] -> Bool
irrefutablePats pat_list = all irrefutablePat pat_list

irrefutablePat (AsPat	_ pat)	= irrefutablePat pat
irrefutablePat (WildPat	_)	= True
irrefutablePat (VarPat	_)	= True
irrefutablePat (LazyPat	_)	= True
irrefutablePat (DictPat ds ms)	= (length ds + length ms) <= 1
irrefutablePat other		= False

failureFreePat :: OutPat id -> Bool

failureFreePat (WildPat _) 		  = True
failureFreePat (VarPat _)  		  = True
failureFreePat (LazyPat	_) 		  = True
failureFreePat (AsPat _ pat)		  = failureFreePat pat
failureFreePat (ConPat con tys _ _ pats)  = only_con con && all failureFreePat pats
failureFreePat (RecPat con _ _ _ fields)  = only_con con && and [ failureFreePat pat | (_,pat,_) <- fields ]
failureFreePat (ListPat _ _)		  = False
failureFreePat (PArrPat _ _)		  = False
failureFreePat (TuplePat pats _)	  = all failureFreePat pats
failureFreePat (DictPat _ _)		  = True
failureFreePat other_pat		  = False   -- Literals, NPat

only_con con = maybeToBool (maybeTyConSingleCon (dataConTyCon con))
\end{code}

\begin{code}
isWildPat (WildPat _) = True
isWildPat other	      = False

patsAreAllCons :: [OutPat id] -> Bool
patsAreAllCons pat_list = all isConPat pat_list

isConPat (AsPat _ pat)		= isConPat pat
isConPat (ConPat _ _ _ _ _)	= True
isConPat (ListPat _ _)		= True
isConPat (PArrPat _ _)		= True
isConPat (TuplePat _ _)		= True
isConPat (RecPat _ _ _ _ _)	= True
isConPat (DictPat ds ms)	= (length ds + length ms) > 1
isConPat other			= False

patsAreAllLits :: [OutPat id] -> Bool
patsAreAllLits pat_list = all isLitPat pat_list

isLitPat (AsPat _ pat)	       = isLitPat pat
isLitPat (LitPat _ _)	       = True
isLitPat (NPat   _ _ _)	       = True
isLitPat (NPlusKPat _ _ _ _ _) = True
isLitPat other		       = False
\end{code}

This function @collectPatBinders@ works with the ``collectBinders''
functions for @HsBinds@, etc.  The order in which the binders are
collected is important; see @HsBinds.lhs@.

\begin{code}
collectPatBinders :: InPat a -> [a]
collectPatBinders pat = collect pat []

collectOutPatBinders :: OutPat a -> [a]
collectOutPatBinders pat = collectOut pat []

collectPatsBinders :: [InPat a] -> [a]
collectPatsBinders pats = foldr collect [] pats

collect WildPatIn	      	 bndrs = bndrs
collect (VarPatIn var)      	 bndrs = var : bndrs
collect (LitPatIn _)	      	 bndrs = bndrs
collect (SigPatIn pat _)	 bndrs = collect pat bndrs
collect (LazyPatIn pat)     	 bndrs = collect pat bndrs
collect (AsPatIn a pat)     	 bndrs = a : collect pat bndrs
collect (NPlusKPatIn n _ _)      bndrs = n : bndrs
collect (NPatIn _ _)		 bndrs = bndrs
collect (ConPatIn c pats)   	 bndrs = foldr collect bndrs pats
collect (ConOpPatIn p1 c f p2)   bndrs = collect p1 (collect p2 bndrs)
collect (ParPatIn  pat)     	 bndrs = collect pat bndrs
collect (ListPatIn pats)    	 bndrs = foldr collect bndrs pats
collect (PArrPatIn pats)    	 bndrs = foldr collect bndrs pats
collect (TuplePatIn pats _)  	 bndrs = foldr collect bndrs pats
collect (RecPatIn c fields) 	 bndrs = foldr (\ (f,pat,_) bndrs -> collect pat bndrs) bndrs fields
-- Generics
collect (TypePatIn ty)           bndrs = bndrs
-- assume the type variables do not need to be bound

-- collect the bounds *value* variables in renamed patterns; type variables
-- are *not* collected
--
collectOut (WildPat _)	      	    bndrs = bndrs
collectOut (VarPat var)      	    bndrs = var : bndrs
collectOut (LazyPat pat)     	    bndrs = collectOut pat bndrs
collectOut (AsPat a pat)     	    bndrs = a : collectOut pat bndrs
collectOut (ListPat _ pats)  	    bndrs = foldr collectOut bndrs pats
collectOut (PArrPat _ pats)  	    bndrs = foldr collectOut bndrs pats
collectOut (TuplePat pats _) 	    bndrs = foldr collectOut bndrs pats
collectOut (ConPat _ _ _ ds pats)   bndrs = ds ++ foldr collectOut bndrs pats
collectOut (RecPat _ _ _ ds fields) bndrs = ds ++ foldr comb bndrs fields
  where
    comb (_, pat, _) bndrs = collectOut pat bndrs
collectOut (LitPat _ _)	      	    bndrs = bndrs
collectOut (NPat _ _ _)		    bndrs = bndrs
collectOut (NPlusKPat n _ _ _ _)    bndrs = n : bndrs
collectOut (DictPat ids1 ids2)      bndrs = ids1 ++ ids2 ++ bndrs
\end{code}

\begin{code}
collectSigTysFromPats :: [InPat name] -> [HsType name]
collectSigTysFromPats pats = foldr collect_pat [] pats

collectSigTysFromPat :: InPat name -> [HsType name]
collectSigTysFromPat pat = collect_pat pat []

collect_pat (SigPatIn pat ty)	   acc = collect_pat pat (ty:acc)
collect_pat WildPatIn	      	   acc = acc
collect_pat (VarPatIn var)         acc = acc
collect_pat (LitPatIn _)	   acc = acc
collect_pat (LazyPatIn pat)        acc = collect_pat pat acc
collect_pat (AsPatIn a pat)        acc = collect_pat pat acc
collect_pat (NPatIn _ _)	   acc = acc
collect_pat (NPlusKPatIn n _ _)    acc = acc
collect_pat (ConPatIn c pats)      acc = foldr collect_pat acc pats
collect_pat (ConOpPatIn p1 c f p2) acc = collect_pat p1 (collect_pat p2 acc)
collect_pat (ParPatIn  pat)        acc = collect_pat pat acc
collect_pat (ListPatIn pats)       acc = foldr collect_pat acc pats
collect_pat (PArrPatIn pats)       acc = foldr collect_pat acc pats
collect_pat (TuplePatIn pats _)    acc = foldr collect_pat acc pats
collect_pat (RecPatIn c fields)    acc = foldr (\ (f,pat,_) acc -> collect_pat pat acc) acc fields
-- Generics
collect_pat (TypePatIn ty)         acc = ty:acc
\end{code}

