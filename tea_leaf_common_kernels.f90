MODULE tea_leaf_kernel_common_module

IMPLICIT NONE

    integer, parameter::stride = 4

    INTEGER(KIND=4), parameter :: block_size=8
    INTEGER(KIND=4), parameter :: kstep = block_size*stride
    INTEGER(KIND=4), parameter :: jstep = block_size

CONTAINS

SUBROUTINE tea_leaf_kernel_init_common(x_min,  &
                           x_max,                  &
                           y_min,                  &
                           y_max,                  &
                           density,                &
                           energy,                 &
                           u,                      &
                           u0,                     &
                           r,                      &
                           w,                      &
                           Kx,                     &
                           Ky,                     &
                           rx,                     &
                           ry,                     &
                           coef)

  IMPLICIT NONE

  INTEGER(KIND=4):: x_min,x_max,y_min,y_max
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: density, energy
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: u, u0, r, w, Kx, Ky

  INTEGER(KIND=4) :: coef
  INTEGER(KIND=4) :: j,k

  REAL(KIND=8) ::  rx, ry

   INTEGER         ::            CONDUCTIVITY        = 1 &
                                ,RECIP_CONDUCTIVITY  = 2

!$OMP PARALLEL
!$OMP DO 
  DO k=y_min, y_max
    DO j=x_min, x_max
      u(j,k) = energy(j,k)*density(j,k)
      u0(j,k) = energy(j,k)*density(j,k)
    ENDDO
  ENDDO
!$OMP END DO

  IF(coef .EQ. RECIP_CONDUCTIVITY) THEN
!$OMP DO 
    ! use w as temp val
    DO k=y_min-1,y_max+1
      DO j=x_min-1,x_max+1
         w(j  ,k  )=1.0_8/density(j  ,k  )
      ENDDO
    ENDDO
!$OMP END DO
  ELSE IF(coef .EQ. CONDUCTIVITY) THEN
!$OMP DO
    DO k=y_min-1,y_max+1
      DO j=x_min-1,x_max+1
         w(j  ,k  )=density(j  ,k  )
      ENDDO
    ENDDO
!$OMP END DO
  ENDIF

!$OMP DO
   DO k=y_min,y_max+1
     DO j=x_min,x_max+1
          Kx(j,k)=(w(j-1,k  ) + w(j,k))/(2.0_8*w(j-1,k  )*w(j,k))
          Ky(j,k)=(w(j  ,k-1) + w(j,k))/(2.0_8*w(j  ,k-1)*w(j,k))
     ENDDO
   ENDDO
!$OMP END DO

!$OMP DO
    DO k=y_min,y_max
        DO j=x_min,x_max
            w(j, k) = (1.0_8                                      &
                + ry*(Ky(j, k+1) + Ky(j, k))                      &
                + rx*(Kx(j+1, k) + Kx(j, k)))*u(j, k)             &
                - ry*(Ky(j, k+1)*u(j, k+1) + Ky(j, k)*u(j, k-1))  &
                - rx*(Kx(j+1, k)*u(j+1, k) + Kx(j, k)*u(j-1, k))

            r(j, k) = u(j, k) - w(j, k)
            !r(j, k) = u(j, k)! This is required to make a zero initial guess to match petsc errant behaviour
                              ! Only works one timestep is run
        ENDDO
    ENDDO
!$OMP END DO
!$OMP END PARALLEL

END SUBROUTINE tea_leaf_kernel_init_common

! Finalise routine is used by both implementations
SUBROUTINE tea_leaf_kernel_finalise(x_min,    &
                           x_max,             &
                           y_min,             &
                           y_max,             &
                           energy,            &
                           density,           &
                           u)

  IMPLICIT NONE

  INTEGER(KIND=4):: x_min,x_max,y_min,y_max
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: u
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: energy
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: density

  INTEGER(KIND=4) :: j,k

!$OMP PARALLEL
!$OMP DO
  DO k=y_min, y_max
    DO j=x_min, x_max
      energy(j,k) = u(j,k) / density(j,k)
    ENDDO
  ENDDO
!$OMP END DO
!$OMP END PARALLEL

END SUBROUTINE tea_leaf_kernel_finalise

SUBROUTINE tea_leaf_calc_residual(x_min,       &
                                  x_max,       &
                                  y_min,       &
                                  y_max,       &
                                  u ,          &
                                  u0,          &
                                  r,           &
                                  Kx,          &
                                  Ky,          &
                                  rx, ry       )

  IMPLICIT NONE

  INTEGER(KIND=4):: x_min,x_max,y_min,y_max
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: u0, u, r
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: Kx
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: Ky

  REAL(KIND=8) :: smvp, rx, ry

  INTEGER(KIND=4) :: j,k

!$OMP PARALLEL
!$OMP DO private(smvp)
    DO k=y_min, y_max
      DO j=x_min, x_max
        smvp = (1.0_8                                         &
            + ry*(Ky(j, k+1) + Ky(j, k))                      &
            + rx*(Kx(j+1, k) + Kx(j, k)))*u(j, k)             &
            - ry*(Ky(j, k+1)*u(j, k+1) + Ky(j, k)*u(j, k-1))  &
            - rx*(Kx(j+1, k)*u(j+1, k) + Kx(j, k)*u(j-1, k))
        r(j, k) = u0(j, k) - smvp
      ENDDO
    ENDDO
!$OMP END DO
!$OMP END PARALLEL

END SUBROUTINE tea_leaf_calc_residual

SUBROUTINE tea_leaf_calc_2norm_kernel(x_min, &
                          x_max,             &
                          y_min,             &
                          y_max,             &
                          arr,               &
                          norm)

  IMPLICIT NONE

  INTEGER(KIND=4):: x_min,x_max,y_min,y_max
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: arr
  REAL(KIND=8) :: norm
  integer :: j, k

  norm = 0.0_8

!$OMP PARALLEL
!$OMP DO REDUCTION(+:norm)
    DO k=y_min,y_max
        DO j=x_min,x_max
            norm = norm + arr(j, k)*arr(j, k)
        ENDDO
    ENDDO
!$OMP END DO
!$OMP END PARALLEL

end SUBROUTINE tea_leaf_calc_2norm_kernel

#define COEF_A (-Ky(j, k)*ry)
#define COEF_B (1.0_8 + ry*(Ky(j, k+1) + Ky(j, k)) + rx*(Kx(j+1, k) + Kx(j, k)))
#define COEF_C (-Ky(j, k+1)*ry)

subroutine tea_block_init(x_min,             &
                           x_max,             &
                           y_min,             &
                           y_max,             &
                           cp,                     &
                           bfp,                     &
                           Kx, Ky, rx, ry)

  IMPLICIT NONE

  INTEGER(KIND=4):: j, ko, k, bottom, top
  INTEGER(KIND=4):: x_min,x_max,y_min,y_max
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: cp, bfp, Kx, Ky
  REAL(KIND=8) :: rx, ry

!$OMP DO PRIVATE(j, bottom, top, ko, k)
    DO ko=y_min,y_max,stride

      bottom = ko
      top = ko + stride - 1

!$OMP SIMD
      do j=x_min, x_max
        k = bottom
        cp(j,k) = COEF_C/COEF_B

        DO k=bottom+1,top
            bfp(j, k) = 1.0_8/(COEF_B - COEF_A*cp(j, k-1))
            cp(j, k) = COEF_C*bfp(j, k)
        ENDDO
      enddo
    ENDDO
!$OMP END DO

end subroutine

subroutine tea_block_solve(x_min,             &
                           x_max,             &
                           y_min,             &
                           y_max,             &
                           r,                 &
                           z,                 &
                           cp,                     &
                           bfp,                     &
                           Kx, Ky, rx, ry)

  IMPLICIT NONE

  INTEGER(KIND=4):: j, ko, k, s, bottom, top, jo, ki
  INTEGER(KIND=4):: x_min,x_max,y_min,y_max
  REAL(KIND=8), DIMENSION(x_min-2:x_max+2,y_min-2:y_max+2) :: cp, bfp, Kx, Ky, r, z
  REAL(KIND=8) :: rx, ry
  REAL(KIND=8), dimension(0:stride-1) :: dp_l, z_l

!$OMP DO PRIVATE(j, bottom, top, ko, k, ki, jo)
    DO ko=y_min,y_max - kstep, kstep
      do ki=ko,ko + kstep - 1,stride
        bottom = ki
        top = ki + stride - 1

        do jo=x_min,x_max - jstep,jstep
!$OMP SIMD PRIVATE(dp_l, z_l)
          do j=jo,jo+jstep - 1
            k = bottom
            dp_l(k-bottom) = r(j, k)/COEF_B

            DO k=bottom+1,top
              dp_l(k-bottom) = (r(j, k) - COEF_A*dp_l(k-bottom-1))*bfp(j, k)
            ENDDO

            k=top
            z_l(k-bottom) = dp_l(k-bottom)

            DO k=top-1, bottom, -1
              z_l(k-bottom) = dp_l(k-bottom) - cp(j, k)*z_l(k-bottom+1)
            ENDDO

            DO k=bottom,top
              z(j, k) = z_l(k-bottom)
            ENDDO
          enddo
        enddo
      enddo
    ENDDO
!$OMP END DO

end subroutine

END MODULE tea_leaf_kernel_common_module

