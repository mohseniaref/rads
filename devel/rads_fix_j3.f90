!-----------------------------------------------------------------------
! Copyright (c) 2011-2016  Remko Scharroo
! See LICENSE.TXT file for copying and redistribution conditions.
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU Lesser General Public License as
! published by the Free Software Foundation, either version 3 of the
! License, or (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!-----------------------------------------------------------------------

!*rads_fix_j3 -- Patch RADS altimeter files of Jason-3 for various anomalies
!
! This program makes numerous patches to the Jason-3 RADS data processed
! by rads_gen_j3. These patches include:
!
! sig0:
! - Adjust backscatter coefficient for apparent off-nadir angle
!
! wind:
! - Recompute wind speed from adjusted sigma0 based on Collard model
!
! usage: rads_fix_j3 [data-selectors] [options]
!
! References:
! Quartly, G. D., Optimizing sigma0 information from Jason-2 altimeter,
! IEEE Geosci. Rem. Sens. Lett., 6(3), 398–402,
! doi:10.1109/LGRS.2009.2013973, 2009.
!-----------------------------------------------------------------------
program rads_fix_j3

use rads
use rads_devel
use meteo_subs

! Data variables

type(rads_sat) :: S
type(rads_pass) :: P

! Other local variables

real(eightbytereal), parameter :: dsig0_ku = -2.40d0, dsig0_c = -0.73d0	! Ku- and C-band Sigma0 bias of Jason-1
integer(fourbyteint) :: i, cyc, pass
logical :: lsig0 = .false.

! Scan command line for options

call synopsis ('--head')
call rads_set_options (' sig0 all')
call rads_init (S)
do i = 1,rads_nopt
	select case (rads_opt(i)%opt)
	case ('sig0')
		lsig0 = .true.
	case ('all')
		lsig0 = .true.
	end select
enddo

! Run process for all files

do cyc = S%cycles(1),S%cycles(2),S%cycles(3)
	do pass = S%passes(1),S%passes(2),S%passes(3)
		call rads_open_pass (S, P, cyc, pass, .true.)
		if (P%ndata > 0) call process_pass (P%ndata)
		call rads_close_pass (S, P)
	enddo
enddo

contains

!-----------------------------------------------------------------------
! Print synopsis
!-----------------------------------------------------------------------

subroutine synopsis (flag)
character(len=*), optional :: flag
if (rads_version ('Patch Jason-3 data for several anomalies', flag=flag)) return
call synopsis_devel (' [processing_options]')
write (*,1310)
1310 format (/ &
'Additional [processing_options] are:' / &
'  --sig0                    Adjust backscatter coefficient for apparent off-nadir angle' / &
'  --all                     All of the above')
stop
end subroutine synopsis

!-----------------------------------------------------------------------
! Process a single pass
!-----------------------------------------------------------------------

subroutine process_pass (n)
integer(fourbyteint), intent(in) :: n
real(eightbytereal) :: sig0_ku(n), sig0_c(n), psi2(n)

call log_pass (P)

! Adjust backscatter for correlation with off-nadir angle (See Quartly [2009])

if (lsig0) then
	call rads_get_var (S, P, 'off_nadir_angle2_wf_ku', psi2, .true.)
	call rads_get_var (S, P, 'sig0_ku', sig0_ku, .true.)
	call rads_get_var (S, P, 'sig0_c', sig0_c, .true.)
	sig0_ku = sig0_ku - 11.34d0 * psi2 + dsig0_ku
	sig0_c  = sig0_c  -  2.01d0 * psi2 + dsig0_c
endif


! Update history

call rads_put_passinfo (S, P)
call rads_put_history (S, P)

! Write out all the data

if (lsig0) then
	call rads_put_var (S, P, 'sig0_ku', sig0_ku)
	call rads_put_var (S, P, 'sig0_c' , sig0_c)
endif

call log_records (n)
end subroutine process_pass

end program rads_fix_j3
