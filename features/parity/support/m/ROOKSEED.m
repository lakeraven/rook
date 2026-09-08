ROOKSEED ; ROOK #99 parity harness - FileMan seeding, v1 ; no raw global SETs
 ;
 ; Seeds canonical RPMS records through the FileMan API (UPDATE^DIE) so BGP
 ; sees real PCC data, never hand-poked globals. Reads of globals/DDs are
 ; fine; every WRITE goes through FileMan so input transforms and cross-
 ; references (including V-file dependent-entry bookkeeping) fire.
 ;
 ; Conventions: entries W one line "OK^<ien>" or "ERR^<detail>". All values
 ; arrive in FileMan INTERNAL format (dates 3YYMMDD[.HHMM], sex F/M, codes
 ; as codes). Patients are namespaced ZZROOKPARITY,* (test-record custom).
 Q
 ;
SETUP ; minimal Kernel user context — what any background job carries.
 ; Cross-references on the V files read DUZ/DUZ("AG"); direct mode has no
 ; signon, so establish the standard programmer/background context.
 S:'$D(DUZ) DUZ=1
 S:'$D(DUZ(0)) DUZ(0)="@"
 S:$G(DUZ("AG"))="" DUZ("AG")="I"
 S:'$G(DUZ(2)) DUZ(2)=+$O(^AUTTLOC(0))
 Q
 ;
PT(ID,SEX,DOB,BEN,COMM) ;EP - patient: file 2 + DINUMed 9000001
 N U,FDA,IENA,MSG,DFN,BIEN,CIEN S U="^"
 D SETUP
 S BIEN="" I $G(BEN)]"" D BENIEN(.BIEN,BEN) I BIEN="" W "ERR^no beneficiary code ",BEN,! Q
 S CIEN="" I $G(COMM)]"" S CIEN=+$O(^AUTTCOM("B",COMM,0)) I 'CIEN W "ERR^no community ",COMM,! Q
 S FDA(2,"+1,",.01)="ZZROOKPARITY,"_ID
 S FDA(2,"+1,",.02)=SEX
 S FDA(2,"+1,",.03)=DOB
 D UPDATE^DIE("","FDA","IENA","MSG")
 I $D(MSG("DIERR")) W "ERR^file2: ",$G(MSG("DIERR",1,"TEXT",1)),! Q
 S DFN=+$G(IENA(1)) I 'DFN W "ERR^no dfn",! Q
 K FDA,IENA,MSG
 S IENA(1)=DFN
 S FDA(9000001,"+1,",.01)=DFN
 I BIEN]"" S FDA(9000001,"+1,",1111)=BIEN
 I CIEN]"" S FDA(9000001,"+1,",1118)=CIEN
 D UPDATE^DIE("","FDA","IENA","MSG")
 I $D(MSG("DIERR")) W "ERR^file9000001: ",$G(MSG("DIERR",1,"TEXT",1)),! Q
 W "OK^",DFN,!
 Q
 ;
VST(DFN,DT,SC,CLIN) ;EP - visit: file 9000010 (type I, first location)
 N U,FDA,IENA,MSG,LOC,CIEN S U="^"
 D SETUP
 S LOC=+$O(^AUTTLOC(0)) I 'LOC W "ERR^no location on twin",! Q
 S CIEN="" I $G(CLIN)]"" S CIEN=+$O(^DIC(40.7,"C",CLIN,0)) I 'CIEN W "ERR^no clinic ",CLIN,! Q
 S FDA(9000010,"+1,",.01)=DT
 S FDA(9000010,"+1,",.02)=DT
 S FDA(9000010,"+1,",.03)="I"
 S FDA(9000010,"+1,",.05)=DFN
 S FDA(9000010,"+1,",.06)=LOC
 S FDA(9000010,"+1,",.07)=SC
 I CIEN]"" S FDA(9000010,"+1,",.08)=CIEN
 D UPDATE^DIE("","FDA","IENA","MSG")
 I $D(MSG("DIERR")) W "ERR^file9000010: ",$G(MSG("DIERR",1,"TEXT",1)),! Q
 W "OK^",+$G(IENA(1)),!
 Q
 ;
POV(VIEN,DFN,CODE) ;EP - V POV: file 9000010.07
 N U,FDA,IENA,MSG,ICD,NAR S U="^"
 D SETUP
 D FINDICD(.ICD,CODE) I 'ICD W "ERR^no icd ",CODE,! Q
 D NARR(.NAR) I 'NAR W "ERR^no provider narrative",! Q
 S FDA(9000010.07,"+1,",.01)=ICD
 S FDA(9000010.07,"+1,",.02)=DFN
 S FDA(9000010.07,"+1,",.03)=VIEN
 S FDA(9000010.07,"+1,",.04)=NAR
 D UPDATE^DIE("","FDA","IENA","MSG")
 I $D(MSG("DIERR")) W "ERR^vpov: ",$G(MSG("DIERR",1,"TEXT",1)),! Q
 W "OK^",+$G(IENA(1)),!
 Q
 ;
PRB(DFN,CODE,STA,ONSET,ENT) ;EP - problem list: file 9000011
 N U,FDA,IENA,MSG,ICD,NAR,LOC,NUM S U="^"
 D SETUP
 D FINDICD(.ICD,CODE) I 'ICD W "ERR^no icd ",CODE,! Q
 D NARR(.NAR) I 'NAR W "ERR^no provider narrative",! Q
 S LOC=+$O(^AUTTLOC(0))
 D NXTNMBR(.NUM,DFN)
 S FDA(9000011,"+1,",.01)=ICD
 S FDA(9000011,"+1,",.02)=DFN
 S FDA(9000011,"+1,",.05)=NAR
 S FDA(9000011,"+1,",.06)=LOC
 S FDA(9000011,"+1,",.07)=NUM
 S FDA(9000011,"+1,",.12)=STA
 I $G(ONSET)]"" S FDA(9000011,"+1,",.13)=ONSET
 I $G(ENT)]"" S FDA(9000011,"+1,",.08)=ENT
 D UPDATE^DIE("","FDA","IENA","MSG")
 I $D(MSG("DIERR")) W "ERR^prob: ",$G(MSG("DIERR",1,"TEXT",1)),! Q
 W "OK^",+$G(IENA(1)),!
 Q
 ;
SHOW(DFN) ;EP - read-back: beneficiary code, community, visit count via APIs
 N U,C,V,N S U="^"
 S C=0,V=0 F  S V=$O(^AUPNVSIT("AC",DFN,V)) Q:V'=+V  S C=C+1
 W $P($G(^DPT(DFN,0)),U,1,3),"|BEN=",$$BEN^AUPNPAT(DFN,"C"),"|VISITS=",C,!
 Q
 ;
BENIEN(R,C) ; beneficiary ien by code (piece 2 of AUTTBEN 0-node)
 N I S R="",I=0 F  S I=$O(^AUTTBEN(I)) Q:I'=+I  I $P($G(^AUTTBEN(I,0)),U,2)=C S R=I Q
 Q
 ;
ENSBEN(CODE,NAME) ;EP - ensure a standard BENEFICIARY (9999999.25) row exists.
 ; Reference-table setup for blank-slate twins (the standard IHS table row,
 ; e.g. "INDIAN/ALASKA NATIVE"^01, was not shipped in the FOIA baseline).
 N U,R,FDA,IENA,MSG S U="^"
 D SETUP
 D BENIEN(.R,CODE) I R D  W "OK^",R,! Q
 . ; idempotent name repair through FileMan when the row exists misnamed
 . Q:$P($G(^AUTTBEN(R,0)),U)=NAME
 . N FDA,MSG S FDA(9999999.25,R_",",.01)=NAME D FILE^DIE("","FDA","MSG")
 S FDA(9999999.25,"+1,",.01)=NAME
 S FDA(9999999.25,"+1,",.02)=CODE
 D UPDATE^DIE("","FDA","IENA","MSG")
 I $D(MSG("DIERR")) W "ERR^benef: ",$G(MSG("DIERR",1,"TEXT",1)),! Q
 W "OK^",+$G(IENA(1)),!
 Q
 ;
NARR(R) ; resolve-or-create the harness provider narrative (9999999.27)
 N U,FDA,IENA,MSG S U="^"
 S R=+$O(^AUTNPOV("B","ROOK PARITY SEED",0)) Q:R
 S FDA(9999999.27,"+1,",.01)="ROOK PARITY SEED"
 D UPDATE^DIE("","FDA","IENA","MSG")
 S R=+$G(IENA(1))
 Q
 ;
NXTNMBR(R,DFN) ; next problem NMBR for the patient (read-only walk)
 N I,N S R=1,I=0
 F  S I=$O(^AUPNPROB("AC",DFN,I)) Q:I'=+I  S N=+$P($G(^AUPNPROB(I,0)),"^",7) I N'<R S R=N+1
 Q
 ;
FINDICD(R,C) ; icd ien via the padded "BA" cross-reference
 N K S R=0,K=C
 F  S K=$O(^ICD9("BA",K)) Q:K=""!($E(K,1,$L(C))'=C)  I $$RTRIM(K)=C S R=+$O(^ICD9("BA",K,0)) Q
 Q
 ;
RTRIM(X) ;
 N I F I=$L(X):-1:1 Q:$E(X,I)'=" "
 Q $E(X,1,I)
 ;
PLTAX(DFN,TAX,B,E,Z) ;EP - micro-parity: run the REAL BGP building block
 ; against a seeded patient. W piece 1 of $$PLTAXNDR^BGPXDU (1 or empty).
 N U,X S U="^"
 D SETUP
 S X=$$PLTAXNDR^BGPXDU(DFN,TAX,B,E,Z)
 W "OK^",+X,!
 Q
