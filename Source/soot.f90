MODULE SOOT_ROUTINES

USE PRECISION_PARAMETERS
USE MESH_POINTERS
USE GLOBAL_CONSTANTS, ONLY: N_PARTICLE_BINS, MIN_PARTICLE_DIAMETER, MAX_PARTICLE_DIAMETER, K_BOLTZMANN, &
                            N_TRACKED_SPECIES, GRAV, AGGLOMERATION_SMIX_INDEX, AGGLOMERATION_SPEC_INDEX, N_AGGLOMERATION_SPECIES
IMPLICIT NONE

PUBLIC CALC_AGGLOMERATION, INITIALIZE_AGGLOMERATION,SETTLING_VELOCITY,PARTICLE_RADIUS, SOOT_SURFACE_OXIDATION

REAL(EB) :: MIN_AGGLOMERATION=1.E-4_EB
REAL(EB), ALLOCATABLE, DIMENSION(:) :: BIN_S
REAL(EB), ALLOCATABLE, DIMENSION(:,:) :: BIN_M, BIN_X,MOBILITY_FAC,A_FAC,PARTICLE_RADIUS
REAL(EB), ALLOCATABLE, DIMENSION(:,:,:) :: PHI_B_FAC,PHI_G_FAC,PHI_S_FAC,PHI_I_FAC,FU1_FAC,FU2_FAC,PARTICLE_MASS
REAL(EB), ALLOCATABLE, DIMENSION(:,:,:,:) :: BIN_ETA
INTEGER, ALLOCATABLE, DIMENSION(:,:,:,:) :: BIN_ETA_INDEX

CONTAINS

SUBROUTINE SETTLING_VELOCITY(NM)
! Routine for gravitational sedimentation and
! thermophoretic movement in gas phase.

USE PHYSICAL_FUNCTIONS, ONLY: GET_VISCOSITY,GET_CONDUCTIVITY
USE GLOBAL_CONSTANTS, ONLY: PREDICTOR,GVEC,SOLID_BOUNDARY,OPEN_BOUNDARY,INTERPOLATED_BOUNDARY,&
                            GRAVITATIONAL_SETTLING,THERMOPHORETIC_SETTLING
REAL(EB) :: ZZ_GET(1:N_TRACKED_SPECIES),TMP_G,MU_G,K_G,KN,KN_FAC,CN,ALPHA,RHS,DTDN,PRES_G,RHO_G,GRAV_FAC,GRAV_VEL
REAL(EB), PARAMETER :: CS=1.17_EB,CT=2.2_EB,CM=1.146_EB
REAL(EB), PARAMETER :: CM3=3._EB*CM,CS2=CS*2._EB,CT2=2._EB*CT
INTEGER, INTENT(IN) :: NM
INTEGER :: I,J,K,N,IW,IIG,JJG,KKG,IOR
REAL(EB), POINTER, DIMENSION(:,:,:) :: U_SETTLE=>NULL(),V_SETTLE=>NULL(),W_SETTLE=>NULL(),RHOP=>NULL()
REAL(EB), POINTER, DIMENSION(:,:,:,:) :: ZZP=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()

CALL POINT_TO_MESH(NM)

IF (PREDICTOR) THEN
   RHOP => RHO
   ZZP  => ZZ
ELSE
   RHOP => RHOS
   ZZP  => ZZS
ENDIF

U_SETTLE => WORK7
V_SETTLE => WORK8
W_SETTLE => WORK9

SPEC_LOOP: DO N=1,N_TRACKED_SPECIES
   IF (.NOT.SPECIES_MIXTURE(N)%DEPOSITING) CYCLE SPEC_LOOP
   U_SETTLE = 0._EB
   V_SETTLE = 0._EB
   W_SETTLE = 0._EB
   IF (GRAVITATIONAL_SETTLING) GRAV_FAC = SPECIES_MIXTURE(N)%MEAN_DIAMETER**2*SPECIES_MIXTURE(N)%DENSITY_SOLID/18._EB
   DO K=0,KBAR
      DO J=0,JBAR
         ILOOP: DO I=0,IBAR
            IF (SOLID(CELL_INDEX(I,J,K))) CYCLE ILOOP
            TMP_G = 0.5_EB*(TMP(I,J,K)+TMP(I+1,J,K))
            ZZ_GET(1:N_TRACKED_SPECIES) = 0.5_EB*(ZZP(I,J,K,1:N_TRACKED_SPECIES)+ZZP(I+1,J,K,1:N_TRACKED_SPECIES))
            RHO_G = 0.5_EB*(RHOP(I,J,K)+RHOP(I+1,J,K))
            PRES_G=0.5_EB*(PBAR(K,PRESSURE_ZONE(I,J,K))+PBAR(K,PRESSURE_ZONE(I+1,J,K)))
            DTDN = -(TMP(I+1,J,K)-TMP(I,J,K))*RDXN(I)
            CALL GET_VISCOSITY(ZZ_GET,MU_G,TMP_G)
            KN_FAC = SQRT(2._EB*PI/(PRES_G*RHO_G))*MU_G
            IF (THERMOPHORETIC_SETTLING) THEN
               KN = KN_FAC/SPECIES_MIXTURE(N)%THERMOPHORETIC_DIAMETER
               CN = CUNNINGHAM(KN)
               CALL GET_CONDUCTIVITY(ZZ_GET,K_G,TMP_G)
               ALPHA = K_G/SPECIES_MIXTURE(N)%CONDUCTIVITY_SOLID
               U_SETTLE(I,J,K) = U_SETTLE(I,J,K) + CS2*(ALPHA+CT*KN)*CN/((1._EB+CM3*KN)*(1+2*ALPHA+CT2*KN)) * &
                                 MU_G/(TMP_G*RHO_G)*DTDN
            ENDIF
            IF (GRAVITATIONAL_SETTLING) THEN
               KN = KN_FAC/SPECIES_MIXTURE(N)%MEAN_DIAMETER
               CN = CUNNINGHAM(KN)
               GRAV_VEL = GRAV_FAC*CN/MU_G
               U_SETTLE(I,J,K) = U_SETTLE(I,J,K) + GVEC(1)*GRAV_VEL
            ENDIF

            TMP_G = 0.5_EB*(TMP(I,J,K)+TMP(I,J+1,K))
            ZZ_GET(1:N_TRACKED_SPECIES) = 0.5_EB*(ZZP(I,J,K,1:N_TRACKED_SPECIES)+ZZP(I,J+1,K,1:N_TRACKED_SPECIES))
            RHO_G = 0.5_EB*(RHOP(I,J,K)+RHOP(I,J+1,K))
            PRES_G=0.5_EB*(PBAR(K,PRESSURE_ZONE(I,J,K))+PBAR(K,PRESSURE_ZONE(I,J+1,K)))
            DTDN = -(TMP(I,J+1,K)-TMP(I,J,K))*RDYN(J)
            CALL GET_VISCOSITY(ZZ_GET,MU_G,TMP_G)
            KN_FAC = SQRT(2._EB*PI/(PRES_G*RHO_G))*MU_G
            IF (THERMOPHORETIC_SETTLING) THEN
               KN = KN_FAC/SPECIES_MIXTURE(N)%THERMOPHORETIC_DIAMETER
               CN = CUNNINGHAM(KN)
               CALL GET_CONDUCTIVITY(ZZ_GET,K_G,TMP_G)
               ALPHA = K_G/SPECIES_MIXTURE(N)%CONDUCTIVITY_SOLID
               V_SETTLE(I,J,K) = V_SETTLE(I,J,K) + CS2*(ALPHA+CT*KN)*CN/((1._EB+CM3*KN)*(1+2*ALPHA+CT2*KN)) * &
                                 MU_G/(TMP_G*RHO_G)*DTDN
            ENDIF
            IF (GRAVITATIONAL_SETTLING) THEN
               KN = KN_FAC/SPECIES_MIXTURE(N)%MEAN_DIAMETER
               CN = CUNNINGHAM(KN)
               GRAV_VEL = GRAV_FAC*CN/MU_G
               V_SETTLE(I,J,K) = V_SETTLE(I,J,K) + GVEC(2)*GRAV_VEL
            ENDIF

            TMP_G = 0.5_EB*(TMP(I,J,K)+TMP(I,J,K+1))
            ZZ_GET(1:N_TRACKED_SPECIES) = 0.5_EB*(ZZP(I,J,K,1:N_TRACKED_SPECIES)+ZZP(I,J,K+1,1:N_TRACKED_SPECIES))
            RHO_G = 0.5_EB*(RHOP(I,J,K)+RHOP(I,J,K+1))
            PRES_G=0.5_EB*(PBAR(K,PRESSURE_ZONE(I,J,K))+PBAR(K,PRESSURE_ZONE(I,J,K+1)))
            DTDN = -(TMP(I,J,K+1)-TMP(I,J,K))*RDZN(K)
            CALL GET_VISCOSITY(ZZ_GET,MU_G,TMP_G)
            KN_FAC = SQRT(2._EB*PI/(PRES_G*RHO_G))*MU_G
            IF (THERMOPHORETIC_SETTLING) THEN
               KN = KN_FAC/SPECIES_MIXTURE(N)%THERMOPHORETIC_DIAMETER
               CN = CUNNINGHAM(KN)
               CALL GET_CONDUCTIVITY(ZZ_GET,K_G,TMP_G)
               ALPHA = K_G/SPECIES_MIXTURE(N)%CONDUCTIVITY_SOLID
               W_SETTLE(I,J,K) = W_SETTLE(I,J,K) + CS2*(ALPHA+CT*KN)*CN/((1._EB+CM3*KN)*(1+2*ALPHA+CT2*KN)) * &
                                MU_G/(TMP_G*RHO_G)*DTDN
            ENDIF
            IF (GRAVITATIONAL_SETTLING) THEN
               KN = KN_FAC/SPECIES_MIXTURE(N)%MEAN_DIAMETER
               CN = CUNNINGHAM(KN)
               GRAV_VEL = GRAV_FAC*CN/MU_G
               W_SETTLE(I,J,K) = W_SETTLE(I,J,K) + GVEC(3)*GRAV_VEL
            ENDIF
         ENDDO ILOOP
      ENDDO
   ENDDO

   ! Wall removal handled by wall BC

   WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
      WC => WALL(IW)
      IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY .OR. &
            WC%BOUNDARY_TYPE==OPEN_BOUNDARY .OR. &
            WC%BOUNDARY_TYPE==INTERPOLATED_BOUNDARY) CYCLE WALL_LOOP
      IIG = WC%ONE_D%IIG
      JJG = WC%ONE_D%JJG
      KKG = WC%ONE_D%KKG
      IOR = WC%ONE_D%IOR
      SELECT CASE(IOR)
         CASE (-1)
            U_SETTLE(IIG,JJG,KKG)   = 0._EB
         CASE ( 1)
            U_SETTLE(IIG-1,JJG,KKG) = 0._EB
         CASE (-2)
            V_SETTLE(IIG,JJG,KKG)   = 0._EB
         CASE ( 2)
            V_SETTLE(IIG,JJG-1,KKG) = 0._EB
         CASE (-3)
            W_SETTLE(IIG,JJG,KKG)   = 0._EB
         CASE ( 3)
            W_SETTLE(IIG,JJG,KKG-1) = 0._EB
      END SELECT
   ENDDO WALL_LOOP

   DO K=1,KBAR
      DO J=1,JBAR
         DO I=1,IBAR
            IF (SOLID(CELL_INDEX(I,J,K))) CYCLE

            RHS = ( R(I)*FX(I,J,K,N)*U_SETTLE(I,J,K) - R(I-1)*FX(I-1,J,K,N)*U_SETTLE(I-1,J,K) )*RDX(I)*RRN(I) &
                + (      FY(I,J,K,N)*V_SETTLE(I,J,K) -        FY(I,J-1,K,N)*V_SETTLE(I,J-1,K) )*RDY(J)        &
                + (      FZ(I,J,K,N)*W_SETTLE(I,J,K) -        FZ(I,J,K-1,N)*W_SETTLE(I,J,K-1) )*RDZ(K)

            DEL_RHO_D_DEL_Z(I,J,K,N) = DEL_RHO_D_DEL_Z(I,J,K,N) - RHS
         ENDDO
      ENDDO
   ENDDO
ENDDO SPEC_LOOP

END SUBROUTINE SETTLING_VELOCITY


SUBROUTINE DEPOSITION_BC(DT,NM)

USE GLOBAL_CONSTANTS, ONLY: EVACUATION_ONLY,SOLID_PHASE_ONLY,SOLID_BOUNDARY,N_TRACKED_SPECIES,TURBULENT_DEPOSITION, PREDICTOR
INTEGER, INTENT(IN) :: NM
REAL(EB), INTENT(IN) :: DT
REAL(EB):: TAU_PLUS_C
INTEGER:: N,IW,ICF
TYPE(SPECIES_MIXTURE_TYPE), POINTER :: SM=>NULL()
TYPE(SPECIES_TYPE), POINTER :: SS=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()
TYPE(SURFACE_TYPE), POINTER :: SU=>NULL()
TYPE(CFACE_TYPE), POINTER :: CFA=>NULL()

IF (PREDICTOR) RETURN
IF (EVACUATION_ONLY(NM)) RETURN
IF (SOLID_PHASE_ONLY) RETURN

CALL POINT_TO_MESH(NM)
SMIX_LOOP: DO N=1,N_TRACKED_SPECIES
   SM=>SPECIES_MIXTURE(N)
   IF (.NOT.SM%DEPOSITING) CYCLE SMIX_LOOP
   SS=>SPECIES(SPECIES_MIXTURE(N)%SINGLE_SPEC_INDEX)
   IF (TURBULENT_DEPOSITION) TAU_PLUS_C = SM%DENSITY_SOLID*SM%MEAN_DIAMETER**2/18._EB

   WALL_CELL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
      WC=>WALL(IW)
      !No deposition if the boundary isn't solid or has a specified flow
      IF (WC%BOUNDARY_TYPE/=SOLID_BOUNDARY .OR. WC%NODE_INDEX /= 0) CYCLE WALL_CELL_LOOP
      SU=>SURFACE(WC%SURF_INDEX)
      IF (ABS(SU%VEL)>TWO_EPSILON_EB .OR. ANY(ABS(SU%MASS_FLUX)>TWO_EPSILON_EB) .OR. ABS(SU%VOLUME_FLOW)>TWO_EPSILON_EB) &
         CYCLE WALL_CELL_LOOP
      CALL CALC_DEPOSITION(WALL_INDEX=IW)
   ENDDO WALL_CELL_LOOP

   CFACE_LOOP: DO ICF=1,N_CFACE_CELLS
      CFA=>CFACE(ICF)
      IF (CFA%BOUNDARY_TYPE/=SOLID_BOUNDARY) CYCLE CFACE_LOOP
      SU=>SURFACE(CFA%SURF_INDEX)
      IF (ABS(SU%VEL)>TWO_EPSILON_EB .OR. ANY(ABS(SU%MASS_FLUX)>TWO_EPSILON_EB) .OR. ABS(SU%VOLUME_FLOW)>TWO_EPSILON_EB) &
         CYCLE CFACE_LOOP
      CALL CALC_DEPOSITION(CFACE_INDEX=ICF)
   ENDDO CFACE_LOOP

ENDDO SMIX_LOOP

CONTAINS

SUBROUTINE CALC_DEPOSITION(WALL_INDEX,CFACE_INDEX)
USE PHYSICAL_FUNCTIONS, ONLY: GET_VISCOSITY,GET_CONDUCTIVITY
USE GLOBAL_CONSTANTS, ONLY: K_BOLTZMANN,GRAVITATIONAL_DEPOSITION,TURBULENT_DEPOSITION,THERMOPHORETIC_DEPOSITION,GVEC
INTEGER, INTENT(IN), OPTIONAL :: WALL_INDEX,CFACE_INDEX
REAL(EB), PARAMETER :: CS=1.17_EB,CT=2.2_EB,CM=1.146_EB
REAL(EB), PARAMETER :: CM3=3._EB*CM,CS2=CS*2._EB,CT2=2._EB*CT
REAL(EB), PARAMETER :: ZZ_MIN_DEP=1.E-14_EB
REAL(EB) :: U_THERM,U_TURB,TGAS,TWALL,MU_G,Y_AEROSOL,RHOG,ZZ_GET(1:N_TRACKED_SPECIES),YDEP,K_G,TMP_FILM,ALPHA,DTMPDX,&
            TAU_PLUS,U_GRAV,D_SOLID,MW_RATIO,KN,KN_FAC, NVEC(3)
INTEGER  :: IIG,JJG,KKG
TYPE(ONE_D_M_AND_E_XFER_TYPE), POINTER :: ONE_D=>NULL()

U_THERM = 0._EB
U_TURB = 0._EB
U_GRAV = 0._EB


IF (PRESENT(WALL_INDEX)) THEN
   ONE_D => WC%ONE_D
   NVEC=(/0._EB,0._EB,0._EB/)
   SELECT CASE(ONE_D%IOR)
      CASE( 1); NVEC(1)= 1._EB
      CASE(-1); NVEC(1)=-1._EB
      CASE( 2); NVEC(2)= 1._EB
      CASE(-2); NVEC(2)=-1._EB
      CASE( 3); NVEC(3)= 1._EB
      CASE(-3); NVEC(3)=-1._EB
   END SELECT
ELSEIF (PRESENT(CFACE_INDEX)) THEN
   ONE_D => CFA%ONE_D
   NVEC  = CFA%NVEC
ENDIF

IIG = ONE_D%IIG
JJG = ONE_D%JJG
KKG = ONE_D%KKG
ZZ_GET(1:N_TRACKED_SPECIES) = MAX(0._EB,ONE_D%ZZ_G(1:N_TRACKED_SPECIES))
IF (ZZ_GET(N) < ZZ_MIN_DEP) RETURN
MW_RATIO = SPECIES_MIXTURE(N)%RCON/ONE_D%RSUM_G
TWALL = ONE_D%TMP_F
TGAS = ONE_D%TMP_G
RHOG = ONE_D%RHO_G
TMP_FILM = 0.5_EB*(TGAS+TWALL)
CALL GET_VISCOSITY(ZZ_GET,MU_G,TMP_FILM)
CALL GET_CONDUCTIVITY(ZZ_GET,K_G,TMP_FILM)
KN_FAC = MU_G*SQRT(2._EB*PI/(PBAR(KKG,PRESSURE_ZONE(IIG,JJG,KKG))*RHOG))
ALPHA = K_G/SM%CONDUCTIVITY_SOLID
DTMPDX = ONE_D%HEAT_TRANS_COEF*(TGAS-TWALL)/K_G
IF (THERMOPHORETIC_DEPOSITION) THEN
   KN = KN_FAC/SM%THERMOPHORETIC_DIAMETER
   U_THERM = CS2*(ALPHA+CT*KN)*CUNNINGHAM(KN)/((1._EB+CM3*KN)*(1+2*ALPHA+CT2*KN)) * MU_G/(TGAS*RHOG)*DTMPDX
ENDIF
IF (GRAVITATIONAL_DEPOSITION) THEN
   KN = KN_FAC/SM%MEAN_DIAMETER
   U_GRAV = - DOT_PRODUCT(GVEC,NVEC)*CUNNINGHAM(KN)*SM%MEAN_DIAMETER**2*SM%DENSITY_SOLID/(18._EB*MU_G)
   ! Prevent negative settling velocity at downward facing surfaces
   U_GRAV = MAX(0._EB,U_GRAV)
ENDIF
IF (TURBULENT_DEPOSITION) THEN
   KN = KN_FAC/SM%MEAN_DIAMETER
   TAU_PLUS = TAU_PLUS_C/MU_G**2*ONE_D%U_TAU**2*RHOG
   IF (TAU_PLUS < 0.2_EB) THEN ! Diffusion regime
      D_SOLID = K_BOLTZMANN*TGAS*CUNNINGHAM(KN)/(3._EB*PI*MU_G*SM%MEAN_DIAMETER)
      U_TURB = ONE_D%U_TAU * 0.086_EB*(MU_G/RHOG/D_SOLID)**(-0.7_EB)
   ELSEIF (TAU_PLUS >= 0.2_EB .AND. TAU_PLUS < 22.9_EB) THEN ! Diffusion-impaction regime
      U_TURB = ONE_D%U_TAU * 3.5E-4_EB * TAU_PLUS**2
   ELSE ! Inertia regime
      U_TURB = ONE_D%U_TAU * 0.17_EB
   ENDIF
ENDIF

IF (PRESENT(WALL_INDEX)) THEN
   WC%V_DEP = MAX(0._EB,U_THERM+U_TURB+U_GRAV+ONE_D%U_NORMAL)
   IF (WC%V_DEP <= TWO_EPSILON_EB) RETURN
   ZZ_GET = ZZ_GET * RHOG
   Y_AEROSOL = ZZ_GET(N)
   YDEP = Y_AEROSOL*MIN(1._EB,(WC%V_DEP)*DT*ONE_D%RDN)
   ZZ_GET(N) = Y_AEROSOL - YDEP
   IF (SM%AWM_INDEX > 0) ONE_D%AWM_AEROSOL(SM%AWM_INDEX)= ONE_D%AWM_AEROSOL(SM%AWM_INDEX)+YDEP/ONE_D%RDN
   IF (SS%AWM_INDEX > 0) ONE_D%AWM_AEROSOL(SS%AWM_INDEX)= ONE_D%AWM_AEROSOL(SS%AWM_INDEX)+YDEP/ONE_D%RDN
ENDIF
IF (PRESENT(CFACE_INDEX)) THEN
   CFA%V_DEP = MAX(0._EB,U_THERM+U_TURB+U_GRAV+ONE_D%U_NORMAL)
   IF (CFA%V_DEP <= TWO_EPSILON_EB) RETURN
   ZZ_GET = ZZ_GET * RHOG
   Y_AEROSOL = ZZ_GET(N)
   YDEP = Y_AEROSOL*MIN(1._EB,(CFA%V_DEP)*DT*ONE_D%RDN)
   ZZ_GET(N) = Y_AEROSOL - YDEP
   IF (SM%AWM_INDEX > 0) ONE_D%AWM_AEROSOL(SM%AWM_INDEX)= ONE_D%AWM_AEROSOL(SM%AWM_INDEX)+YDEP/ONE_D%RDN
   IF (SS%AWM_INDEX > 0) ONE_D%AWM_AEROSOL(SS%AWM_INDEX)= ONE_D%AWM_AEROSOL(SS%AWM_INDEX)+YDEP/ONE_D%RDN
ENDIF

D_SOURCE(IIG,JJG,KKG) = D_SOURCE(IIG,JJG,KKG) - MW_RATIO*YDEP / RHOG / DT
M_DOT_PPP(IIG,JJG,KKG,N) = M_DOT_PPP(IIG,JJG,KKG,N) - YDEP / DT

END SUBROUTINE CALC_DEPOSITION

END SUBROUTINE DEPOSITION_BC


SUBROUTINE INITIALIZE_AGGLOMERATION
INTEGER :: N,I,II,III
REAL(EB) :: E_PK,MIN_PARTICLE_MASS,MAX_PARTICLE_MASS

ALLOCATE(BIN_S(N_AGGLOMERATION_SPECIES))
ALLOCATE(BIN_M(N_AGGLOMERATION_SPECIES,0:MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(BIN_X(N_AGGLOMERATION_SPECIES,1:MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(BIN_ETA(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS),2))
ALLOCATE(BIN_ETA_INDEX(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS),2))
BIN_ETA = 0._EB
BIN_ETA_INDEX = -1

ALLOCATE(PHI_B_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(PARTICLE_MASS(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(PHI_G_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(PHI_S_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(PHI_I_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(FU1_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(FU2_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(MOBILITY_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(A_FAC(N_AGGLOMERATION_SPECIES,MAXVAL(N_PARTICLE_BINS)))
ALLOCATE(PARTICLE_RADIUS(N_AGGLOMERATION_SPECIES,1:MAXVAL(N_PARTICLE_BINS)))

SPEC_LOOP: DO N = 1, N_AGGLOMERATION_SPECIES

   MIN_PARTICLE_MASS = 0.125_EB*FOTHPI * SPECIES(AGGLOMERATION_SPEC_INDEX(N))%DENSITY_SOLID*MIN_PARTICLE_DIAMETER(N)**3
   MAX_PARTICLE_MASS = 0.125_EB*FOTHPI * SPECIES(AGGLOMERATION_SPEC_INDEX(N))%DENSITY_SOLID*MAX_PARTICLE_DIAMETER(N)**3
   BIN_S(N) = (MAX_PARTICLE_MASS/MIN_PARTICLE_MASS)**(1._EB/REAL(N_PARTICLE_BINS(N),EB))

   BIN_M(N,0)= MIN_PARTICLE_MASS
   DO I=1,N_PARTICLE_BINS(N)
      BIN_M(N,I) = BIN_M(N,I-1)*BIN_S(N)
      BIN_X(N,I) = 2._EB*BIN_M(N,I)/(1._EB+BIN_S(N))
   ENDDO



   DO I=1,N_PARTICLE_BINS(N)
      PARTICLE_RADIUS(N,I) = (BIN_X(N,I) / FOTHPI / SPECIES(AGGLOMERATION_SPEC_INDEX(N))%DENSITY_SOLID)**ONTH
      MOBILITY_FAC(N,I) = 1._EB/(6._EB*PI*PARTICLE_RADIUS(N,I))
      A_FAC(N,I) = SQRT(2._EB*K_BOLTZMANN*BIN_X(N,I)/PI)
   END DO
   DO I=1,N_PARTICLE_BINS(N)
      DO II=1,N_PARTICLE_BINS(N)
         PARTICLE_MASS(N,I,II) = BIN_X(N,I) + BIN_X(N,II)
         E_PK = MIN(PARTICLE_RADIUS(N,I),PARTICLE_RADIUS(N,II))**2/(2._EB*(PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))**2)
         PHI_G_FAC(N,I,II) = E_PK*(PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))**2*GRAV
         PHI_B_FAC(N,I,II)= 4._EB*PI*K_BOLTZMANN*(PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))
         !Check what Re and r are for PHI_I and _S
         PHI_S_FAC(N,I,II) = E_PK*(PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))**3*SQRT(8._EB*PI/15._EB)
         PHI_I_FAC(N,I,II) = E_PK*(PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))**2*(512._EB*PI**3/15._EB)**0.25_EB
         !Check Fu1 formula*******
         FU1_FAC(N,I,II) = (PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))/K_BOLTZMANN*&
                         SQRT(8._EB*K_BOLTZMANN/PI*(1._EB/BIN_X(N,I)+1._EB/BIN_X(N,II)))
         FU2_FAC(N,I,II) = 2._EB/(PARTICLE_RADIUS(N,I)+PARTICLE_RADIUS(N,II))
         BINDO:DO III=2,N_PARTICLE_BINS(N)
            IF (PARTICLE_MASS(N,I,II) > BIN_X(N,N_PARTICLE_BINS(N))) THEN
               BIN_ETA_INDEX(N,I,II,:) = N_PARTICLE_BINS(N)
               BIN_ETA(N,I,II,:) = 0.5_EB*BIN_X(N,N_PARTICLE_BINS(N))/PARTICLE_MASS(N,I,II)
               EXIT BINDO
            ELSE
               IF (PARTICLE_MASS(N,I,II) > BIN_X(N,III-1) .AND. PARTICLE_MASS(N,I,II) < BIN_X(N,III)) THEN
                  BIN_ETA_INDEX(N,I,II,1) = III-1
                  BIN_ETA(N,I,II,1) = (BIN_X(N,III)-PARTICLE_MASS(N,I,II))/(BIN_X(N,III)-BIN_X(N,III-1))
                  BIN_ETA_INDEX(N,I,II,2) = III
                  BIN_ETA(N,I,II,2) = (PARTICLE_MASS(N,I,II)-BIN_X(N,III-1))/(BIN_X(N,III)-BIN_X(N,III-1))
                  IF (I==II) BIN_ETA(N,I,II,:) = BIN_ETA(N,I,II,:) *0.5_EB
                  EXIT BINDO
               ENDIF
            ENDIF
         ENDDO BINDO
      ENDDO
   ENDDO
   BIN_ETA(N,N_PARTICLE_BINS(N),N_PARTICLE_BINS(N),1) = 1._EB
   BIN_ETA_INDEX(N,N_PARTICLE_BINS(N),N_PARTICLE_BINS(N),1) = N_PARTICLE_BINS(N)
   BIN_ETA(N,N_PARTICLE_BINS(N),N_PARTICLE_BINS(N),2) = 0._EB
   BIN_ETA_INDEX(N,N_PARTICLE_BINS(N),N_PARTICLE_BINS(N),2) = N_PARTICLE_BINS(N)

ENDDO SPEC_LOOP

END SUBROUTINE INITIALIZE_AGGLOMERATION


SUBROUTINE CALC_AGGLOMERATION(DT,NM)
USE PHYSICAL_FUNCTIONS,ONLY:GET_VISCOSITY
INTEGER :: I,J,K,NS,N,NN,IM1,IM2,JM1,JM2,KM1,KM2,IP1,JP1,KP1
INTEGER, INTENT(IN) :: NM
REAL(EB), INTENT(IN) :: DT
REAL(EB) :: DUDX,DVDY,DWDZ,ONTHDIV,S11,S22,S33,DUDY,DUDZ,DVDX,DVDZ,DWDX,DWDY,S12,S23,S13,STRAIN_RATE,DISSIPATION_RATE
REAL(EB) :: KN,MFP,N_I(MAXVAL(N_PARTICLE_BINS)),N0(MAXVAL(N_PARTICLE_BINS)),N1(MAXVAL(N_PARTICLE_BINS)),&
            N2(MAXVAL(N_PARTICLE_BINS)),N3(MAXVAL(N_PARTICLE_BINS)),&
            RHOG,TMPG,MUG,TERMINAL(MAXVAL(N_PARTICLE_BINS)),&
            FU,MOBILITY(MAXVAL(N_PARTICLE_BINS)),ZZ_GET(1:N_TRACKED_SPECIES),AM,AMT(MAXVAL(N_PARTICLE_BINS)),&
            PHI_B,PHI_S,PHI_G,PHI_I,PHI(MAXVAL(N_PARTICLE_BINS),MAXVAL(N_PARTICLE_BINS)),VREL,FU1,FU2,DT_SUBSTEP,DT_SUM,TOL
REAL(EB), PARAMETER :: AMFAC=2._EB*K_BOLTZMANN/PI
CALL POINT_TO_MESH(NM)
ZZ_GET = 0._EB

SPEC_LOOP: DO NS=1,N_AGGLOMERATION_SPECIES

   GEOMETRY_LOOP:DO K=1,KBAR
      DO J=1,JBAR
         DO I=1,IBAR
            IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
            N0(1:N_PARTICLE_BINS(NS))=ZZ(I,J,K,AGGLOMERATION_SMIX_INDEX(NS):AGGLOMERATION_SMIX_INDEX(NS)+N_PARTICLE_BINS(NS)-1)
            RHOG = RHO(I,J,K)
            N0 = N0*RHOG/BIN_X(NS,:)
            IF (ALL(N0 < MIN_AGGLOMERATION)) CYCLE
            ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(I,J,K,1:N_TRACKED_SPECIES)
            TMPG = TMP(I,J,K)
            CALL GET_VISCOSITY(ZZ_GET,MUG,TMPG)
            MFP = MUG*SQRT(PI/(2._EB*PBAR(K,PRESSURE_ZONE(I,J,K))*RHOG))
            IM1 = MAX(0,I-1)
            JM1 = MAX(0,J-1)
            KM1 = MAX(0,K-1)
            IM2 = MAX(1,I-1)
            JM2 = MAX(1,J-1)
            KM2 = MAX(1,K-1)
            IP1 = MIN(IBAR,I+1)
            JP1 = MIN(JBAR,J+1)
            KP1 = MIN(KBAR,K+1)
            DUDX = RDX(I)*(U(I,J,K)-U(IM1,J,K))
            DVDY = RDY(J)*(V(I,J,K)-V(I,JM1,K))
            DWDZ = RDZ(K)*(W(I,J,K)-W(I,J,KM1))
            ONTHDIV = ONTH*(DUDX+DVDY+DWDZ)
            S11 = DUDX - ONTHDIV
            S22 = DVDY - ONTHDIV
            S33 = DWDZ - ONTHDIV
            DUDY = 0.25_EB*RDY(J)*(U(I,JP1,K)-U(I,JM2,K)+U(IM1,JP1,K)-U(IM1,JM2,K))
            DUDZ = 0.25_EB*RDZ(K)*(U(I,J,KP1)-U(I,J,KM2)+U(IM1,J,KP1)-U(IM1,J,KM2))
            DVDX = 0.25_EB*RDX(I)*(V(IP1,J,K)-V(IM2,J,K)+V(IP1,JM1,K)-V(IM2,JM1,K))
            DVDZ = 0.25_EB*RDZ(K)*(V(I,J,KP1)-V(I,J,KM2)+V(I,JM1,KP1)-V(I,JM1,KM2))
            DWDX = 0.25_EB*RDX(I)*(W(IP1,J,K)-W(IM2,J,K)+W(IP1,J,KM1)-W(IM2,J,KM1))
            DWDY = 0.25_EB*RDY(J)*(W(I,JP1,K)-W(I,JM2,K)+W(I,JP1,KM1)-W(I,JM2,KM1))
            S12 = 0.5_EB*(DUDY+DVDX)
            S13 = 0.5_EB*(DUDZ+DWDX)
            S23 = 0.5_EB*(DVDZ+DWDY)
            STRAIN_RATE = 2._EB*(S11**2 + S22**2 + S33**2 + 2._EB*(S12**2 + S13**2 + S23**2))
            DISSIPATION_RATE = MU(I,J,K)/RHOG*STRAIN_RATE
            N_I = N0
            DO N=1,N_PARTICLE_BINS(NS)
               KN=MFP/PARTICLE_RADIUS(NS,N)
               !Verify CN
               MOBILITY(N) = CUNNINGHAM(KN)*MOBILITY_FAC(NS,N)/MUG
               TERMINAL(N) = MOBILITY(N)*GRAV*BIN_X(NS,N)
               AM = A_FAC(NS,N)*SQRT(TMPG)*MOBILITY(N)
               AMT(N) = ((PARTICLE_RADIUS(NS,N)+AM)**3-(PARTICLE_RADIUS(NS,N)**2+AM**2)**1.5_EB)/&
                        (3._EB*PARTICLE_RADIUS(NS,N)*AM)-PARTICLE_RADIUS(Ns,N)
            ENDDO
            PHI = 0._EB
            DO N=1,N_PARTICLE_BINS(NS)
               DO NN=1,N_PARTICLE_BINS(NS)
                  IF (NN<N) CYCLE
                  FU1 = FU1_FAC(NS,N,NN)/(SQRT(TMPG)*(MOBILITY(N)+MOBILITY(NN)))
                  FU2 = 1._EB+FU2_FAC(NS,N,NN)*SQRT(AMT(NN)**2+AMT(N)**2)
                  FU = 1._EB/FU1+1._EB/FU2
                  FU = 1._EB/FU
                  PHI_B = PHI_B_FAC(NS,N,NN)*(MOBILITY(N)+MOBILITY(NN))*FU*TMPG
                  VREL = ABS(TERMINAL(N)-TERMINAL(NN))
                  PHI_G = PHI_G_FAC(NS,N,NN)*VREL
                  PHI_S = PHI_S_FAC(NS,N,NN)*RHOG/MUG*DISSIPATION_RATE
                  IF (GRAV <= TWO_EPSILON_EB) THEN
                     PHI_I = 0
                  ELSE
                     PHI_I = PHI_I_FAC(NS,N,NN)*(RHOG/MUG*DISSIPATION_RATE**3)**0.25_EB*VREL/GRAV
                  ENDIF
                  PHI(N,NN) = PHI_B+PHI_G+SQRT(PHI_S**2+PHI_I**2)
                  PHI(NN,N) = PHI(N,NN)
               ENDDO
            ENDDO
            DT_SUBSTEP=DT
            DT_SUM = 0._EB
            STEPLOOP: DO WHILE (DT_SUM <DT)
               N1 = 0._EB
               N2 = 0._EB
               N3 = 0._EB
               AGGLOMERATE_LOOP:DO N=1,N_PARTICLE_BINS(NS)
                  DO NN=N,N_PARTICLE_BINS(NS)
                     IF (N0(N)<MIN_AGGLOMERATION .OR. N0(NN)<MIN_AGGLOMERATION) CYCLE
                     !Remove particles that agglomerate
                     N1(N)=N1(N)-PHI(NN,N)*N0(N)*N0(NN)*DT_SUBSTEP
                     IF (NN/=N) N1(NN)=N1(NN)-PHI(NN,N)*N0(N)*N0(NN)*DT_SUBSTEP
                     ! Create new particles from agglomeration
                     N2(BIN_ETA_INDEX(NS,N,NN,1)) = N2(BIN_ETA_INDEX(NS,N,NN,1)) + &
                        BIN_ETA(NS,N,NN,1)*PHI(N,NN)*N0(N)*N0(NN)*DT_SUBSTEP
                     N2(BIN_ETA_INDEX(NS,N,NN,2)) = N2(BIN_ETA_INDEX(NS,N,NN,2)) + &
                        BIN_ETA(NS,N,NN,2)*PHI(N,NN)*N0(N)*N0(NN)*DT_SUBSTEP
                  ENDDO
               ENDDO AGGLOMERATE_LOOP
               N3 = N1 + N2
               N3 = N3 + N0
               TOL = MAXVAL((N0-N3)/(N0+TINY_EB))
               IF (TOL > 0.3_EB) THEN
                  DT_SUBSTEP = DT_SUBSTEP * 0.3_EB/ TOL
               ELSE
                  DT_SUM = DT_SUM + DT_SUBSTEP
                  DT_SUBSTEP = MIN(DT-DT_SUM,1.5_EB*DT_SUBSTEP)
                  N0 = N3
               ENDIF
            END DO STEPLOOP
            N3 = N3*SUM(N_I*BIN_X(NS,:))/SUM(N3*BIN_X(NS,:))
            ZZ(I,J,K,AGGLOMERATION_SMIX_INDEX(NS):AGGLOMERATION_SMIX_INDEX(NS)+N_PARTICLE_BINS(NS)-1) = N3 * BIN_X(NS,:) / RHOG
         ENDDO
      ENDDO
   ENDDO GEOMETRY_LOOP
ENDDO SPEC_LOOP

END SUBROUTINE CALC_AGGLOMERATION


SUBROUTINE SOOT_SURFACE_OXIDATION(DT,NM)
! Hartman, Beyler, Riahi, Beyler, Fire and Materials (2012), 36:177-184
USE GLOBAL_CONSTANTS, ONLY : R0,SOLID_BOUNDARY,MW_O2,O2_INDEX,SOOT_INDEX,NU_SOOT_OX,ZZ_MIN_GLOBAL
USE PHYSICAL_FUNCTIONS, ONLY: GET_MASS_FRACTION, GET_MOLECULAR_WEIGHT, GET_SPECIFIC_GAS_CONSTANT,&
                              GET_SPECIFIC_HEAT,GET_AVERAGE_SPECIFIC_HEAT
INTEGER,INTENT(IN) :: NM
REAL(EB), INTENT(IN) :: DT
REAL(EB) :: M_SOOT,MW,RHOG,TMPG,E=-211000._EB*1000._EB/R0,A=4.7E10_EB,DMDT,DM,ZZ_GET(1:N_TRACKED_SPECIES),VOL
REAL(EB) :: DZZ(1:N_TRACKED_SPECIES),RSUM_LOC,CP,Y_O2,X_O2, M_DOT_PPP_SINGLE
REAL(EB) :: H_G,CPBAR,CPBAR2,MW_RATIO,DELTA_H_G
INTEGER :: ICF,IW,NS,NS2,IIG,JJG,KKG
TYPE(SPECIES_MIXTURE_TYPE), POINTER :: SM=>NULL()
TYPE(SPECIES_TYPE), POINTER :: SS=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()
TYPE(CFACE_TYPE), POINTER :: CFA=>NULL()
TYPE(ONE_D_M_AND_E_XFER_TYPE), POINTER :: ONE_D

CALL POINT_TO_MESH(NM)

SS => SPECIES(SOOT_INDEX)

WALL_CELL_LOOP: DO IW = 1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC=>WALL(IW)
   ONE_D=>WC%ONE_D
   IF (WC%BOUNDARY_TYPE/=SOLID_BOUNDARY) CYCLE WALL_CELL_LOOP
   IF (ONE_D%AWM_AEROSOL(SS%AWM_INDEX)<ZZ_MIN_GLOBAL) CYCLE WALL_CELL_LOOP
   M_SOOT = ONE_D%AWM_AEROSOL(SS%AWM_INDEX)*WC%ONE_D%AREA
   IIG = ONE_D%IIG
   JJG = ONE_D%JJG
   KKG = ONE_D%KKG
   RHOG = ONE_D%RHO_G
   TMPG = ONE_D%TMP_G
   ZZ_GET(1:N_TRACKED_SPECIES) = MAX(0._EB,ONE_D%ZZ_G(1:N_TRACKED_SPECIES)- M_DOT_PPP(IIG,JJG,KKG,1:N_TRACKED_SPECIES)*DT/RHOG)
   CALL GET_MASS_FRACTION(ZZ_GET,O2_INDEX,Y_O2)
   IF (Y_O2 < ZZ_MIN_GLOBAL) CYCLE
   CALL GET_MOLECULAR_WEIGHT(ZZ_GET,MW)
   X_O2 = Y_O2*MW/MW_O2
   DZZ = 0._EB
   DMDT = A*M_SOOT*X_O2*EXP(E/ONE_D%TMP_F)
   VOL = DX(IIG)*RC(IIG)*DY(JJG)*DZ(KKG)
   DM = MIN(M_SOOT,DMDT*DT,-Y_O2*RHOG*VOL/MINVAL(NU_SOOT_OX))

   DZZ = NU_SOOT_OX *  DM / VOL
   Q(IIG,JJG,KKG) = Q(IIG,JJG,KKG)-SUM(SPECIES_MIXTURE%H_F*DZZ)/DT

   DM = DM / ONE_D%AREA
   IF (SS%AGGLOMERATING) THEN
      M_SOOT = M_SOOT / ONE_D%AREA
      NS2 = SUM(INT(FINDLOC(AGGLOMERATION_SPEC_INDEX,SOOT_INDEX)))
      DO NS=AGGLOMERATION_SMIX_INDEX(NS2),AGGLOMERATION_SMIX_INDEX(NS2)+N_PARTICLE_BINS(NS2)-1
         SM => SPECIES_MIXTURE(NS)
         IF (SM%AWM_INDEX > 0) &
            ONE_D%AWM_AEROSOL(SM%AWM_INDEX) = ONE_D%AWM_AEROSOL(SM%AWM_INDEX) - DM * ONE_D%AWM_AEROSOL(SM%AWM_INDEX)/M_SOOT
      ENDDO
   ENDIF
   ONE_D%AWM_AEROSOL(SS%AWM_INDEX) = ONE_D%AWM_AEROSOL(SS%AWM_INDEX) - DM

   ! Divergence term
   CALL GET_SPECIFIC_HEAT(ZZ_GET,CP,ONE_D%TMP_G)
   H_G = CP*ONE_D%TMP_G

   CALL GET_SPECIFIC_HEAT(ZZ_GET,CP,TMPG)
   CALL GET_SPECIFIC_GAS_CONSTANT(ZZ_GET,RSUM_LOC)
   DO NS=1,N_TRACKED_SPECIES
      IF (ABS(DZZ(NS)) < TWO_EPSILON_EB) CYCLE
      ZZ_GET=0._EB
      ZZ_GET(NS)=1._EB
      M_DOT_PPP_SINGLE = DZZ(NS)/DT
      MW_RATIO = SPECIES_MIXTURE(NS)%RCON/ONE_D%RSUM_G
      IF (DZZ(NS)<0._EB) THEN
         D_SOURCE(IIG,JJG,KKG) = D_SOURCE(IIG,JJG,KKG) + M_DOT_PPP_SINGLE*MW_RATIO/ONE_D%RHO_G
      ELSE
         CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_GET,CPBAR,ONE_D%TMP_G)
         CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_GET,CPBAR2,ONE_D%TMP_F)
         DELTA_H_G = CPBAR2*ONE_D%TMP_F-CPBAR*ONE_D%TMP_G
         D_SOURCE(IIG,JJG,KKG) = D_SOURCE(IIG,JJG,KKG) + M_DOT_PPP_SINGLE*(MW_RATIO + DELTA_H_G/H_G)/ONE_D%RHO_G
         M_DOT_PPP(IIG,JJG,KKG,NS) = M_DOT_PPP(IIG,JJG,KKG,NS) + M_DOT_PPP_SINGLE
      ENDIF
   ENDDO

ENDDO WALL_CELL_LOOP

CFACE_LOOP: DO ICF=1,N_CFACE_CELLS
   CFA=>CFACE(ICF)
   ONE_D=>CFA%ONE_D
   IF (CFA%BOUNDARY_TYPE/=SOLID_BOUNDARY) CYCLE CFACE_LOOP
   IF (ONE_D%AWM_AEROSOL(SS%AWM_INDEX)<ZZ_MIN_GLOBAL) CYCLE CFACE_LOOP
   M_SOOT = ONE_D%AWM_AEROSOL(SS%AWM_INDEX)*CFA%ONE_D%AREA
   IIG = ONE_D%IIG
   JJG = ONE_D%JJG
   KKG = ONE_D%KKG
   RHOG = ONE_D%RHO_G
   TMPG = ONE_D%TMP_G
   ZZ_GET(1:N_TRACKED_SPECIES) = MAX(0._EB,ONE_D%ZZ_G(1:N_TRACKED_SPECIES)- M_DOT_PPP(IIG,JJG,KKG,1:N_TRACKED_SPECIES)*DT/RHOG)
   CALL GET_MASS_FRACTION(ZZ_GET,O2_INDEX,Y_O2)
   IF (Y_O2 < ZZ_MIN_GLOBAL) CYCLE
   CALL GET_MOLECULAR_WEIGHT(ZZ_GET,MW)
   X_O2 = Y_O2*MW/MW_O2
   DZZ = 0._EB
   DMDT = A*M_SOOT*X_O2*EXP(E/ONE_D%TMP_F)
   VOL = DX(IIG)*RC(IIG)*DY(JJG)*DZ(KKG)
   DM = MIN(M_SOOT,DMDT*DT,-Y_O2*RHOG*VOL/MINVAL(NU_SOOT_OX))

   DZZ = NU_SOOT_OX *  DM / VOL
   Q(IIG,JJG,KKG) = Q(IIG,JJG,KKG)-SUM(SPECIES_MIXTURE%H_F*DZZ)/DT

   DM = DM / ONE_D%AREA
   IF (SS%AGGLOMERATING) THEN
      M_SOOT = M_SOOT / ONE_D%AREA
      NS2 = SUM(INT(FINDLOC(AGGLOMERATION_SPEC_INDEX,SOOT_INDEX)))
      DO NS=AGGLOMERATION_SMIX_INDEX(NS2),AGGLOMERATION_SMIX_INDEX(NS2)+N_PARTICLE_BINS(NS2)-1
         SM => SPECIES_MIXTURE(NS)
         IF (SM%AWM_INDEX > 0) &
            ONE_D%AWM_AEROSOL(SM%AWM_INDEX) = ONE_D%AWM_AEROSOL(SM%AWM_INDEX) - DM * ONE_D%AWM_AEROSOL(SM%AWM_INDEX)/M_SOOT
      ENDDO
   ENDIF
   ONE_D%AWM_AEROSOL(SS%AWM_INDEX) = ONE_D%AWM_AEROSOL(SS%AWM_INDEX) - DM

   ! Divergence term
   CALL GET_SPECIFIC_HEAT(ZZ_GET,CP,ONE_D%TMP_G)
   H_G = CP*ONE_D%TMP_G

   CALL GET_SPECIFIC_HEAT(ZZ_GET,CP,TMPG)
   CALL GET_SPECIFIC_GAS_CONSTANT(ZZ_GET,RSUM_LOC)
   DO NS=1,N_TRACKED_SPECIES
      IF (ABS(DZZ(NS)) < TWO_EPSILON_EB) CYCLE
      ZZ_GET=0._EB
      ZZ_GET(NS)=1._EB
      M_DOT_PPP_SINGLE = DZZ(NS)/DT
      MW_RATIO = SPECIES_MIXTURE(NS)%RCON/ONE_D%RSUM_G
      IF (DZZ(NS)<0._EB) THEN
         D_SOURCE(IIG,JJG,KKG) = D_SOURCE(IIG,JJG,KKG) + M_DOT_PPP_SINGLE*MW_RATIO/ONE_D%RHO_G
      ELSE
         CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_GET,CPBAR,ONE_D%TMP_G)
         CALL GET_AVERAGE_SPECIFIC_HEAT(ZZ_GET,CPBAR2,ONE_D%TMP_F)
         DELTA_H_G = CPBAR2*ONE_D%TMP_F-CPBAR*ONE_D%TMP_G
         D_SOURCE(IIG,JJG,KKG) = D_SOURCE(IIG,JJG,KKG) + M_DOT_PPP_SINGLE*(MW_RATIO + DELTA_H_G/H_G)/ONE_D%RHO_G
         M_DOT_PPP(IIG,JJG,KKG,NS) = M_DOT_PPP(IIG,JJG,KKG,NS) + M_DOT_PPP_SINGLE
      ENDIF
   ENDDO

ENDDO CFACE_LOOP

END SUBROUTINE SOOT_SURFACE_OXIDATION


REAL(EB) FUNCTION CUNNINGHAM(KN)
REAL(EB), INTENT(IN) :: KN
REAL(EB), PARAMETER :: K1=1.257_EB,K2=0.4_EB,K3=1.1_EB

CUNNINGHAM = 1._EB+K1*KN+K2*KN*EXP(-K3/KN)

END FUNCTION CUNNINGHAM


SUBROUTINE DROPLET_SCRUBBING(IP,NM,DT,DT_P)
USE GLOBAL_CONSTANTS, ONLY: D_Z
USE PHYSICAL_FUNCTIONS, ONLY: GET_VISCOSITY
INTEGER, INTENT(IN) :: IP,NM
REAL(EB), INTENT(IN) :: DT,DT_P
INTEGER :: IIG,JJG,KKG,NS
REAL(EB) :: VEL,VREL, R_D, FRAC, EFF, EFF_IN, EFF_IM, PE, STK, MU_G, ZZ_GET(1:N_TRACKED_SPECIES)
REAL(EB) :: R_RATIO, EFF_IN_VIS, EFF_IN_POT, EFF_IM_VIS, EFF_IM_POT, RATE, VOL, RE
TYPE (LAGRANGIAN_PARTICLE_TYPE), POINTER :: LP=>NULL()
TYPE(SPECIES_MIXTURE_TYPE), POINTER :: SM=>NULL()

CALL POINT_TO_MESH(NM)

LP => LAGRANGIAN_PARTICLE(IP)
IIG = LP%ONE_D%IIG
JJG = LP%ONE_D%JJG
KKG = LP%ONE_D%KKG
ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KKG,1:N_TRACKED_SPECIES)
CALL GET_VISCOSITY(ZZ_GET,MU_G,TMP(IIG,JJG,KKG))

VEL = SQRT(LP%U**2 + LP%V**2 + LP%W**2)
R_D = LP%ONE_D%X(1)
VOL = 1._EB/(RDX(IIG)*RRN(IIG)*RDY(JJG)*RDZ(KKG))
FRAC = MIN(1._EB,VEL*DT_P*MIN(VOL**TWTH,LP%PWT*PI*R_D**2)/VOL)
VREL = SQRT((LP%U - U(IIG,JJG,KKG))**2 + (LP%V - V(IIG,JJG,KKG))**2 + (LP%W - W(IIG,JJG,KKG))**2)
RE  = RHO(IIG,JJG,KKG)*VREL*2._EB*R_D/MU_G

DO NS=1, N_TRACKED_SPECIES
   SM => SPECIES_MIXTURE(NS)
   IF (.NOT. SM%DEPOSITING) CYCLE
   R_RATIO = 0.5_EB*SM%MEAN_DIAMETER/R_D
   EFF_IN_VIS = (1._EB + R_RATIO)**2._EB * (1._EB - 3._EB/(2._EB*(1._EB + R_RATIO)) + 1._EB/(2._EB*(1._EB + R_RATIO)**3))
   EFF_IN_POT = (1._EB + R_RATIO)**2._EB - (1._EB + R_RATIO)
   EFF_IN = (EFF_IN_VIS + EFF_IN_POT * RE/60._EB)/(1._EB + RE/60._EB)
   STK = 0.5_EB * SM%MEAN_DIAMETER**2._EB * SM%DENSITY_SOLID * VREL / (9._EB*MU_G*R_D)
   IF (STK <= 0.0834_EB) THEN
      EFF_IM_POT = 0._EB
   ELSE
      EFF_IM_POT = (STK / (STK + 0.5_EB))**2._EB
      IF (STK < 0.2_EB) EFF_IM_POT = (STK-0.0834_EB)/(0.2_EB-0.0834_EB)*EFF_IM_POT
   ENDIF
   IF (STK > 1.214_EB) THEN
      EFF_IM_VIS = (1._EB+0.75_EB*LOG(2._EB*STK)/(STK-1.214_EB))**(-2._EB)
   ELSE
      EFF_IM_VIS = 0._EB
   ENDIF
   EFF_IM = (EFF_IM_VIS + EFF_IM_POT * RE/60._EB)/(1._EB + RE/60._EB)
   PE = 2._EB*R_D*VREL/D_Z(INT(TMP(IIG,JJG,KKG)),NS)
   EFF = 1._EB - (1._EB - EFF_IN) * (1._EB - EFF_IM)
   RATE = EFF * FRAC * ZZ_GET(NS) * RHO(IIG,JJG,KKG) / DT
   D_SOURCE(IIG,JJG,KKG) = D_SOURCE(IIG,JJG,KKG) - RATE*SPECIES_MIXTURE(1)%MW/SM%MW/RHO(IIG,JJG,KKG)
   M_DOT_PPP(IIG,JJG,KKG,NS) = M_DOT_PPP(IIG,JJG,KKG,NS) - RATE
ENDDO

END SUBROUTINE DROPLET_SCRUBBING


END MODULE SOOT_ROUTINES
