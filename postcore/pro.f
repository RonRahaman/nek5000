      subroutine load_fld(string)

      include 'SIZE'
      include 'INPUT'
      include 'RESTART'

      character*1 string(132),fout(132),BLNK
      character*6 ext
      DATA BLNK/' '/

      call blank  (initc(1),132)

      L1=0
      DO 100 I=1,132
         IF (STRING(I).EQ.BLNK) GOTO 200
         L1=I
  100 CONTINUE
  200 CONTINUE
      LEN=L1

      call chcopy (initc(1),string,len)
      call setics

      return
      end
c-----------------------------------------------------------------------
      subroutine lambda2(l2)
c
c     Generate Lambda-2 vortex of Jeong & Hussein, JFM '95
c
      include 'SIZE'
      include 'TOTAL'

      real l2(lx1,ly1,lz1,1)

      parameter (lxyz=lx1*ly1*lz1)

      real gije(lxyz,3,3)
      real vv(ldim,ldim),ss(ldim,ldim),oo(ldim,ldim),w(ldim,ldim)
      real lam(ldim)

      nxyz = nx1*ny1*nz1
      n    = nxyz*nelv

      do ie=1,nelv
         ! Compute velocity gradient tensor
         call comp_gije(gije,vx(1,1,1,ie),vy(1,1,1,ie),vz(1,1,1,ie),ie)

         do l=1,nxyz
            ! decompose into symm. and antisymm. part
            do j=1,ndim
            do i=1,ndim
               ss(i,j) = 0.5*(gije(l,i,j)+gije(l,j,i))
               oo(i,j) = 0.5*(gije(l,i,j)-gije(l,j,i))
            enddo
            enddo
         
            call rzero(vv,ldim*ldim)
            do j=1,ndim
            do i=1,ndim
            do k=1,ndim
               vv(i,j) = vv(i,j) + ss(i,k)*ss(k,j) + oo(i,k)*oo(k,j)
            enddo
            enddo
            enddo

c           Solve eigenvalue problemand sort 
c           eigenvalues in ascending order.
            call find_lam3(lam,vv,w,ndim,ierr)

            l2(l,1,1,ie) = lam(2)
         enddo
      enddo

      ! smooth field
      wght = 0.5 
      ncut = 1
      call filter_s0(l2,wght,ncut,'vortx') 

      return
      end
c-----------------------------------------------------------------------
      subroutine find_lam3(lam,aa,w,ndim,ierr)
      real aa(ndim,ndim),lam(ndim),w(ndim,ndim),lam2
c
c     Use cubic eqn. to compute roots
c
      common /ecmnr/ a,b,c,d,e,f,f2,ef,df,r0,r1
      common /ecmni/ nr
      common /ecmnl/ iffout,ifdefl
      logical        iffout,ifdefl
c
c
      iffout = .false.
      ierr = 0
c
c     2D case....
c
c
      if (ndim.eq.2) then
         a = aa(1,1)
         b = aa(1,2)
         c = aa(2,1)
         d = aa(2,2)
         aq = 1.
         bq = -(a+d)
         cq = a*d-c*b
c
         call quadratic(x1,x2,aq,bq,cq,ierr)
c 
         lam(1) = min(x1,x2)
         lam(2) = max(x1,x2)
c
         return
      endif
c
c
c
c
c     Else ...  3D case....
c
c                                    a d e
c     Get symmetric 3x3 matrix       d b f
c                                    e f c
c
      a = aa(1,1)
      b = aa(2,2)
      c = aa(3,3)
      d = 0.5*(aa(1,2)+aa(2,1))
      e = 0.5*(aa(1,3)+aa(3,1))
      f = 0.5*(aa(2,3)+aa(3,2))
      ef = e*f
      df = d*f
      f2 = f*f
c
c
c     Use cubic eqn. to compute roots
c
c     ax = a-x
c     bx = b-x
c     cx = c-x
c     y = ax*(bx*cx-f2) - d*(d*cx-ef) + e*(df-e*bx)
c
      a1 = -(a+b+c)
      a2 =  (a*b+b*c+a*c) - (d*d+e*e+f*f)
      a3 =  a*f*f + b*e*e + c*d*d - a*b*c - 2*d*e*f
c
      call cubic  (lam,a1,a2,a3,ierr)
      call sort   (lam,w,3)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine quadratic(x1,x2,a,b,c,ierr)
c
c     Stable routine for computation of real roots of quadratic
c
      ierr = 0
      x1 = 0.
      x2 = 0.
c
      if (a.eq.0.) then
         if (b.eq.0) then
            if (c.ne.0) then
c              write(6,10) x1,x2,a,b,c
               ierr = 1
            endif
            return
         endif
         ierr = 2
         x1 = -c/b
c        write(6,11) x1,a,b,c
         return
      endif
c
      d = b*b - 4.*a*c
      if (d.lt.0) then
         ierr = 1
c        write(6,12) a,b,c,d
         return
      endif
      if (d.gt.0) d = sqrt(d)
c
      if (b.gt.0) then
         x1 = -2.*c / ( d+b )
         x2 = -( d+b ) / (2.*a)
      else
         x1 =  ( d-b ) / (2.*a)
         x2 = -2.*c / ( d-b )
      endif
c
   10 format('ERROR: Both a & b zero in routine quadratic NO ROOTS.'
     $      ,1p5e12.4)
   11 format('ERROR: a = 0 in routine quadratic, only one root.'
     $      ,1p5e12.4)
   12 format('ERROR: negative discriminate in routine quadratic.'
     $      ,1p5e12.4)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine cubic(xo,ai1,ai2,ai3,ierr)
      real xo(3),ai1,ai2,ai3
      complex*16 x(3),a1,a2,a3,q,r,d,arg,t1,t2,t3,theta,sq,a13
c
c     Compute real solutions to cubic root eqn. (Num. Rec. v. 1, p. 146)
c     pff/Sang-Wook Lee  Jan 19 , 2004
c
c     Assumption is that all x's are *real*
c
      real*8 twopi
      save   twopi
      data   twopi /6.283185307179586476925286766/
c
      ierr = 0
c
      zero = 0.
      a1   = cmplx(ai1,zero)
      a2   = cmplx(ai2,zero)
      a3   = cmplx(ai3,zero)
c
      q = (a1*a1 - 3*a2)/9.
      if (q.eq.0) goto 999
c
      r = (2*a1*a1*a1 - 9*a1*a2 + 27*a3)/54.
c
      d = q*q*q - r*r
c
c     if (d.lt.0) goto 999
c
      arg   = q*q*q
      arg   = sqrt(arg)
      arg   = r/arg
c
      if (abs(arg).gt.1) goto 999
      theta = acos(abs(arg))
c
      t1    = theta / 3.
      t2    = (theta + twopi) / 3.
      t3    = (theta + 2.*twopi) / 3.
c
      sq  = -2.*sqrt(q)
      a13 = a1/3.
      x(1) = sq*cos(t1) - a13
      x(2) = sq*cos(t2) - a13
      x(3) = sq*cos(t3) - a13
c
      xo(1) = real(x(1))
      xo(2) = real(x(2))
      xo(3) = real(x(3))
c
      return
c
  999 continue   ! failed
      ierr = 1
      call rzero(x,3)

      return
      end
c-----------------------------------------------------------------------
      subroutine comp_gije(gije,u,v,w,e)
c
c                                         du_i
c     Compute the gradient tensor G_ij := ----  ,  for element e
c                                         du_j
c
      include 'SIZE'
      include 'TOTAL'

      real gije(lx1*ly1*lz1,ldim,ldim)
      real u   (lx1*ly1*lz1)
      real v   (lx1*ly1*lz1)
      real w   (lx1*ly1*lz1)

      real ur  (lx1*ly1*lz1)
      real us  (lx1*ly1*lz1)
      real ut  (lx1*ly1*lz1)

      integer e

      n    = nx1-1      ! Polynomial degree
      nxyz = nx1*ny1*nz1

      if (if3d) then     ! 3D CASE

        do k=1,3
          if (k.eq.1) call local_grad3(ur,us,ut,u,n,1,dxm1,dxtm1)
          if (k.eq.2) call local_grad3(ur,us,ut,v,n,1,dxm1,dxtm1)
          if (k.eq.3) call local_grad3(ur,us,ut,w,n,1,dxm1,dxtm1)

          do i=1,nxyz
            dj = jacmi(i,e)

            ! d/dx
            gije(i,k,1) = dj*( 
     $      ur(i)*rxm1(i,1,1,e)+us(i)*sxm1(i,1,1,e)+ut(i)*txm1(i,1,1,e))
            ! d/dy
            gije(i,k,2) = dj*( 
     $      ur(i)*rym1(i,1,1,e)+us(i)*sym1(i,1,1,e)+ut(i)*tym1(i,1,1,e))
            ! d/dz
            gije(i,k,3) = dj*(
     $      ur(i)*rzm1(i,1,1,e)+us(i)*szm1(i,1,1,e)+ut(i)*tzm1(i,1,1,e))

          enddo
        enddo

      elseif (ifaxis) then   ! AXISYMMETRIC CASE
            if(nid.eq.0) write(6,*) 
     &        'ABORT: comp_gije no axialsymmetric support for now'
            call exitt
      else              ! 2D CASE

        do k=1,2
          if (k.eq.1) call local_grad2(ur,us,u,n,1,dxm1,dxtm1)
          if (k.eq.2) call local_grad2(ur,us,v,n,1,dxm1,dxtm1)
          do i=1,nxyz
             dj = jacmi(i,e)
             ! d/dx
             gije(i,k,1)=dj*(ur(i)*rxm1(i,1,1,e)+us(i)*sxm1(i,1,1,e))
             ! d/dy 
             gije(i,k,2)=dj*(ur(i)*rym1(i,1,1,e)+us(i)*sym1(i,1,1,e))
          enddo
        enddo
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine filter_s1(scalar,tf,nx,nel) ! filter scalar field 

      include 'SIZE'

      parameter(lxyz=lx1*ly1*lz1) 
      real scalar(lxyz,1)
      real fh(nx*nx),fht(nx*nx),tf(nx)

      real w1(lxyz,lelt)

c     Build 1D-filter based on the transfer function (tf)
      call build_1d_filt(fh,fht,tf,nx,nid)

c     Filter scalar
      call copy(w1,scalar,lxyz*nel)
      do ie=1,nel
         call tens3d1(scalar(1,ie),w1(1,ie),fh,fht,nx1,nx1)  ! fh x fh x fh x scalar
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine filter_s0(scalar,wght,ncut,name5) ! filter scalar field 

      include 'SIZE'
      include 'TOTAL'

      real scalar(1)
      character*5 name5

      parameter (l1=lx1*lx1)
      real intdv(l1),intuv(l1),intdp(l1),intup(l1),intv(l1),intp(l1)
      save intdv    ,intuv    ,intdp    ,intup    ,intv    ,intp

      common /ctmp0/ intt
      common /screv/ wk1,wk2
      common /scrvh/ zgmv,wgtv,zgmp,wgtp,tmax(100)

      real intt (lx1,lx1)
      real wk1  (lx1,lx1,lx1,lelt)
      real wk2  (lx1,lx1,lx1)
      real zgmv (lx1),wgtv(lx1),zgmp(lx1),wgtp(lx1)


      integer icall
      save    icall
      data    icall /0/

      logical ifdmpflt

      imax = nid
      imax = iglmax(imax,1)
      jmax = iglmax(imax,1)

c      if (icall.eq.0) call build_new_filter(intv,zgm1,nx1,ncut,wght,nid)
      call build_new_filter(intv,zgm1,nx1,ncut,wght,nid)

      icall = 1

      call filterq(scalar,intv,nx1,nz1,wk1,wk2,intt,if3d,fmax)
      fmax = glmax(fmax,1)

      if (nid.eq.0) write(6,1) istep,fmax,name5
    1 format(i8,' sfilt:',1pe12.4,a10)

      return
      end
c-----------------------------------------------------------------------
      subroutine intpts_setup(tolin)
c
c setup routine for interpolation tool
c tolin ... stop point seach interation if 1-norm of the step in (r,s,t) 
c           is smaller than tolin 
c
      INCLUDE 'SIZE'
      INCLUDE 'GEOM'

      common /nekmpi/ nidd,npp,nekcomm,nekgroup,nekreal
      common /intp/   ipth,loff,nndim,nmax

      tol = tolin
      if (tolin.lt.0) tol = 1e-13 

      nmax    = lpart            ! max. number of points
      loff    = lx1*ly1*lz1*lelt ! input field offset
      n       = nx1*ny1*nz1*nelt 
      nndim   = ndim
      npt_max = 256
      nxf     = 2*nx1            ! fine mesh for bb-test
      nyf     = nxf
      nzf     = nxf
      bb_t    = 0.01 ! relative size to expand bounding boxes by
c
      call findpts_setup(ipth,nekcomm,npp,nndim,
     &                   xm1,ym1,zm1,nx1,ny1,nz1,
     &                   nelt,nxf,nyf,nzf,bb_t,n,n,
     &                   npt_max,tol)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine intpts(fieldin,nfld,iTl,mi,rTl,mr,n,iffind)
c
c interpolate input field at given points 
c
c in:
c fieldin ... input field(s) to interpolate
c nfld    ... number of fields
c mi      ... stride size of iTl (at least 4)
c mr      ... stride size of rTl (at least 2*nndim+nfld)
c n       ... local number of interpolation points 
c in/out:
c interpolation points (i=1,...,n) are organized list of tuples 
c iTl  ... integer tuple list (4,n)
c    output   (1,i) = processor number (0 to np-1)   
c    output   (2,i) = local element number (1 to nelt)
c    output   (3,i) = return code (-1, 0, 1)
c    output   (4,i) = local point id (only internally used)
c rTl  ... real tuple list (1+2*n+nfld)
c    output   (1,i)      = distance (from located point to given point)
c    input    (2,i)      = x  
c    input    (3,i)      = y  
c    input    (4,i)      = z  (only when ndim=3)
c    output   (ndim+2,i) = r   
c    output   (ndim+3,i) = s   
c    output   (ndim+4,i) = t  (only when ndim=3)
c    output   (1+2*ndim+ifld,i) = interpolated field value (ifld=1,nfld)
c
      real    fieldin (1)
      integer iTl (mi,1)
      real    rTl (mr,1)
      integer iTlS,rTlS

      common /intp/ ipth,loff,nndim,nmax

      logical iffind

      integer icalld
      save    icalld
      data    icalld /0/

      ! do some checks
      if(mi.lt.4 .or. mr.lt.1+2*nndim+nfld) then
        write(6,*) 'ABORT: intpts() invalid tuple size mi/mir', mi, mr
        call exitt
      endif
      if(n.gt.nmax) then
        write(6,*) 
     &   'ABORT: intpts() n>lpart, increase lpartin SIZE ', n, nmax
        call exitt
      endif

      ! set stride size for tuple lists
      iTlS = mi
      rTlS = mr 


      ! locate points (iel,iproc,r,s,t)
      if(icalld.eq.0 .or. iffind) then
        call findpts(ipth,iTl(3,1),iTlS,
     &               iTl(1,1),iTlS,
     &               iTL(2,1),iTlS,
     &               rTl(nndim+2,1),rTlS,
     &               rTl(1,1),rTlS,
     &               rTl(2,1),rTlS,
     &               rTl(3,1),rTlS,
     &               rTl(4,1),rTlS,n)
        icalld = 1
      endif
 
      do in=1,n
         iTl(4,in) = in ! store local id
         ! check return code 
         if(iTl(3,in).eq.1) then
           dist = rTl(1,in)
           write(6,'(A,4E15.7)') 
     &      'WARNING: point on boundary or outside the mesh xy[z]d: ',
     &      (rTl(1+k,in),k=1,nndim),dist
         elseif(iTl(3,in).eq.2) then
           write(6,'(A,3E15.7)') 
     &      'WARNING: point not within mesh xy[z]: !',
     &      (rTl(1+k,in),k=1,nndim)
         endif
      enddo

      ! evaluate inut field at given points
      do ifld = 1,nfld
         ioff = (ifld-1)*loff
         call findpts_eval(ipth,rTl(1+2*nndim+ifld,1),rTlS,
     &                     iTl(3,1),iTlS,
     &                     iTl(1,1),iTlS,
     &                     iTl(2,1),iTlS,
     &                     rTl(nndim+2,1),rTlS,n,
     &                     fieldin(ioff+1))
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine intpts_done()

      common /intp/ ipth,loff,nndim,nmax

      call findpts_free(ipth)

      return
      end
c-----------------------------------------------------------------------
      subroutine tens3d1(v,u,f,ft,nv,nu)  ! v = F x F x F x u

c     Note: this routine assumes that nx1=ny1=nz1
c
      include 'SIZE'
      include 'INPUT'

      parameter (lw=4*lx1*lx1*lz1)
      common /ctensor/ w1(lw),w2(lw)

      real v(nv,nv,nv),u(nu,nu,nu)
      real f(1),ft(1)

      if (nu*nu*nv.gt.lw) then
         write(6,*) nid,nu,nv,lw,' ERROR in tens3d1. Increase lw.'
         call exitt
      endif

      if (if3d) then
         nuv = nu*nv
         nvv = nv*nv
         call mxm(f,nv,u,nu,w1,nu*nu)
         k=1
         l=1
         do iz=1,nu
            call mxm(w1(k),nv,ft,nu,w2(l),nv)
            k=k+nuv
            l=l+nvv
         enddo
         call mxm(w2,nvv,ft,nu,v,nv)
      else
         call mxm(f ,nv,u,nu,w1,nu)
         call mxm(w1,nv,ft,nu,v,nv)
      endif
      return
      end
c-----------------------------------------------------------------------
      subroutine build_1d_filt(fh,fht,trnsfr,nx,nid)
c
c     This routing builds a 1D filter with transfer function diag()
c
c     Here, nx = number of points
c
      real fh(nx,nx),fht(nx,nx),trnsfr(nx)
c
      parameter (lm=40)
      parameter (lm2=lm*lm)
      common /cfiltr/ phi(lm2),pht(lm2),diag(lm2),rmult(lm),Lj(lm)
     $              , zpts(lm)
      real Lj

      common /cfilti/ indr(lm),indc(lm),ipiv(lm)
c
      if (nx.gt.lm) then
         write(6,*) 'ABORT in set_filt:',nx,lm
         call exitt
      endif

      call zwgll(zpts,rmult,nx)

      kj = 0
      n  = nx-1
      do j=1,nx
         z = zpts(j)
         call legendre_poly(Lj,z,n)
         kj = kj+1
         pht(kj) = Lj(1)
         kj = kj+1
         pht(kj) = Lj(2)
         do k=3,nx
            kj = kj+1
            pht(kj) = Lj(k)-Lj(k-2)
         enddo
      enddo
      call transpose (phi,nx,pht,nx)
      call copy      (pht,phi,nx*nx)
      call gaujordf  (pht,nx,nx,indr,indc,ipiv,ierr,rmult)

      call rzero(diag,nx*nx)
      k=1 
      do i=1,nx
         diag(k) = trnsfr(i)
         k = k+(nx+1)
      enddo

      call mxm  (diag,nx,pht,nx,fh,nx)      !          -1
      call mxm  (phi ,nx,fh,nx,pht,nx)      !     V D V

      call copy      (fh,pht,nx*nx)
      call transpose (fht,nx,fh,nx)

      do k=1,nx*nx
         pht(k) = 1.-diag(k)
      enddo
      np1 = nx+1
      if (nid.eq.0) then
         write(6,6) 'flt amp',(pht (k),k=1,nx*nx,np1)
         write(6,6) 'flt trn',(diag(k),k=1,nx*nx,np1)
   6     format(a8,16f7.4,6(/,8x,16f7.4))
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine mag_tensor_e(mag,aije)
c
c     Compute magnitude of tensor A_e for element e
c
c     mag(A_e) = sqrt( 0.5 (A:A) )
c
      include 'SIZE'
      REAL mag (lx1*ly1*lz1)
      REAL aije(lx1*ly1*lz1,ldim,ldim)

      nxyz = nx1*ny1*nz1

      call rzero(mag,nxyz)
 
      do 100 j=1,ndim
      do 100 i=1,ndim
      do 100 l=1,nxyz 
         mag(l) = mag(l) + 0.5*aije(l,i,j)*aije(l,i,j)
 100  continue

      call vsqrt(mag,nxyz)

      return
      end
c-----------------------------------------------------------------------
      subroutine comp_sije(gije)
c
c     Compute symmetric part of a tensor G_ij for element e
c
      include 'SIZE'
      include 'TOTAL'

      real gije(lx1*ly1*lz1,ldim,ldim)

      nxyz = nx1*ny1*nz1

      k = 1

      do j=1,ndim
      do i=k,ndim
         do l=1,nxyz
            gije(l,i,j) = 0.5*(gije(l,i,j)+gije(l,j,i))
            gije(l,j,i) = gije(l,i,j)
         enddo
      enddo
         k = k + 1
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine map2reg(ur,n,u,nel)
c
c     Map scalar field u() to regular n x n x n array ur 
c
      include 'SIZE'
      real ur(1),u(lx1*ly1*lz1,1)

      integer e

      ldr = n**ndim

      k=1
      do e=1,nel
         if (ndim.eq.2) call map2reg_2di_e(ur(k),n,u(1,e),nx1) 
         if (ndim.eq.3) call map2reg_3di_e(ur(k),n,u(1,e),nx1) 
         k = k + ldr
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine map2reg_2di_e(uf,n,uc,m) ! Fine, uniform pt

      real uf(n,n),uc(m,m)

      parameter (l=50)
      common /cmap2d/ j(l*l),jt(l*l),w(l*l),z(l)

      integer mo,no
      save    mo,no
      data    mo,no / 0,0 /

      if (m.gt.l) call exitti('map2reg_2di_e memory 1$',m)
      if (n.gt.l) call exitti('map2reg_2di_e memory 2$',n)

      if (m.ne.mo .or. n.ne.no ) then

          call zwgll (z,w,m)
          call zuni  (w,n)

          call gen_int_gz(j,jt,w,n,z,m)

      endif

      call mxm(j,n,uc,m,w ,m)
      call mxm(w,n,jt,m,uf,n)

      return
      end
c-----------------------------------------------------------------------
      subroutine map2reg_3di_e(uf,n,uc,m) ! Fine, uniform pt

      real uf(n,n,n),uc(m,m,m)

      parameter (l=50)
      common /cmap3d/ j(l*l),jt(l*l),v(l*l*l),w(l*l*l),z(l)

      integer mo,no
      save    mo,no
      data    mo,no / 0,0 /

      if (m.gt.l) call exitti('map2reg_3di_e memory 1$',m)
      if (n.gt.l) call exitti('map2reg_3di_e memory 2$',n)

      if (m.ne.mo .or. n.ne.no ) then

          call zwgll (z,w,m)
          call zuni  (w,n)

          call gen_int_gz(j,jt,w,n,z,m)

      endif

      mm = m*m
      mn = m*n
      nn = n*n

      call mxm(j,n,uc,m,v ,mm)
      iv=1
      iw=1
      do k=1,m
         call mxm(v(iv),n,jt,m,w(iw),n)
         iv = iv+mn
         iw = iw+nn
      enddo
      call mxm(w,nn,jt,m,uf,n)

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_int_gz(j,jt,g,n,z,m)

c     Generate interpolater from m z points to n g points

c        j   = interpolation matrix, mapping from z to g
c        jt  = transpose of interpolation matrix
c        m   = number of points on z grid
c        n   = number of points on g grid

      real j(n,m),jt(m,n),g(n),z(m)

      mpoly  = m-1
      do i=1,n
         call fd_weights_full(g(i),z,mpoly,0,jt(1,i))
      enddo

      call transpose(j,n,jt,m)

      return
      end
c-----------------------------------------------------------------------
      subroutine zuni(z,np)
c
c     Generate equaly spaced np points on the interval [-1:1]
c
      real z(1)

      dz = 2./(np-1)
      z(1) = -1.
      do i = 2,np-1
         z(i) = z(i-1) + dz
      enddo
      z(np) = 1.

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_rea(imid)  ! Generate and output essential parts of .rea
                                ! Clobbers ccurve()
      include 'SIZE'
      include 'TOTAL'

c     imid = 0  ! No midside node defs
c     imid = 1  ! Midside defs where current curve sides don't exist
c     imid = 2  ! All nontrivial midside node defs

      if (nid.eq.0) open(unit=10,file='newrea.out',status='unknown') ! clobbers existing file

      call gen_rea_xyz

      call gen_rea_curve(imid)  ! Clobbers ccurve()

      if (nid.eq.0) write(10,*)' ***** BOUNDARY CONDITIONS *****'
      do ifld=1,nfield
         call gen_rea_bc   (ifld)
      enddo

      if (nid.eq.0) close(10)

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_rea_xyz
      include 'SIZE'
      include 'TOTAL'

      parameter (lv=2**ldim,lblock=1000)
      common /scrns/ xyz(lv,ldim,lblock),wk(lv*ldim*lblock)
      common /scruz/ igr(lblock)

      integer e,eb,eg
      character*1 letapt

      integer isym2pre(8)   ! Symmetric-to-prenek vertex ordering
      save    isym2pre
      data    isym2pre / 1 , 2 , 4 , 3 , 5 , 6 , 8 , 7 /

      letapt = 'a'
      numapt = 1

      nxs = nx1-1
      nys = ny1-1
      nzs = nz1-1
      nblock = lv*ldim*lblock

      letapt = 'a'
      numapt = 1

      nxs = nx1-1
      nys = ny1-1
      nzs = nz1-1
      nblock = lv*ldim*lblock

      if (nid.eq.0) 
     $  write(10,'(3i10,'' NEL,NDIM,NELV'')') nelgt,ndim,nelgv

      do eb=1,nelgt,lblock
         nemax = min(eb+lblock-1,nelgt)
         call rzero(xyz,nblock)
         call izero(igr,lblock)
         kb = 0
         do eg=eb,nemax
            mid = gllnid(eg)
            e   = gllel (eg)
            kb  = kb+1
            l   = 0
            if (mid.eq.nid.and.if3d) then ! fill owning processor
               igr(kb) = igroup(e)
               do k=0,1
               do j=0,1
               do i=0,1
                  l=l+1
                  li=isym2pre(l)
                  xyz(li,1,kb) = xm1(1+i*nxs,1+j*nys,1+k*nzs,e)
                  xyz(li,2,kb) = ym1(1+i*nxs,1+j*nys,1+k*nzs,e)
                  xyz(li,3,kb) = zm1(1+i*nxs,1+j*nys,1+k*nzs,e)
               enddo
               enddo
               enddo
            elseif (mid.eq.nid) then    ! 2D
               igr(kb) = igroup(e)
               do j=0,1
               do i=0,1
                  l =l+1
                  li=isym2pre(l)
                  xyz(li,1,kb) = xm1(1+i*nxs,1+j*nys,1,e)
                  xyz(li,2,kb) = ym1(1+i*nxs,1+j*nys,1,e)
               enddo
               enddo
            endif
         enddo
         call  gop(xyz,wk,'+  ',nblock)  ! Sum across all processors
         call igop(igr,wk,'+  ',nblock)  ! Sum across all processors

         if (nid.eq.0) then
            kb = 0
            do eg=eb,nemax
               kb  = kb+1

               write(10,'(a15,i9,a2,i5,a1,a10,i6)')
     $   '      ELEMENT  ',eg,' [',numapt,letapt,']    GROUP',igr(kb)

               if (if3d) then 

                  write(10,'(4g15.7)')(xyz(ic,1,kb),ic=1,4)
                  write(10,'(4g15.7)')(xyz(ic,2,kb),ic=1,4)
                  write(10,'(4g15.7)')(xyz(ic,3,kb),ic=1,4)

                  write(10,'(4g15.7)')(xyz(ic,1,kb),ic=5,8)
                  write(10,'(4g15.7)')(xyz(ic,2,kb),ic=5,8)
                  write(10,'(4g15.7)')(xyz(ic,3,kb),ic=5,8)

               else ! 2D

                  write(10,'(4g15.7)')(xyz(ic,1,kb),ic=1,4)
                  write(10,'(4g15.7)')(xyz(ic,2,kb),ic=1,4)

               endif

            enddo
         endif
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_rea_curve(imid)

c     This routine is complex because we must first count number of 
c     nontrivial curved sides.

c     A two pass strategy is used:  first count, then write

      include 'SIZE'
      include 'TOTAL'

      integer e,eb,eg
      character*1 cc

      parameter (lblock=500)
      common /scrns/ vcurve(5,12,lblock),wk(5*12*lblock)
      common /scruz/ icurve(12,lblock)

      if (imid.gt.0) then

c        imid = 0  ! No midside node defs
c        imid = 1  ! Midside defs where current curve sides don't exist
c        imid = 2  ! All nontrivial midside node defs

         if (imid.eq.2) call blank(ccurve,12*lelt)

         do e=1,nelt
            call gen_rea_midside_e(e)
         enddo

      endif

      nedge = 4 + 8*(ndim-2)

      ncurvn = 0
      do e=1,nelt
      do i=1,nedge
         if (ccurve(i,e).ne.' ') ncurvn = ncurvn+1
      enddo
      enddo
      ncurvn = iglsum(ncurvn,1)

      if (nid.eq.0) then
         WRITE(10,*)' ***** CURVED SIDE DATA *****'
         WRITE(10,'(I10,A20,A33)') ncurvn,' Curved sides follow',
     $   ' IEDGE,IEL,CURVE(I),I=1,5, CCURVE'
      endif

      do eb=1,nelgt,lblock

         nemax = min(eb+lblock-1,nelgt)
         call izero(icurve,12*lblock)
         call rzero(vcurve,60*lblock)

         kb = 0
         do eg=eb,nemax
            mid = gllnid(eg)
            e   = gllel (eg)
            kb  = kb+1
            if (mid.eq.nid) then ! fill owning processor
               do i=1,nedge
                  icurve(i,kb) = 0
                  if (ccurve(i,e).eq.'C') icurve(i,kb) = 1
                  if (ccurve(i,e).eq.'s') icurve(i,kb) = 2
                  if (ccurve(i,e).eq.'m') icurve(i,kb) = 3
                  call copy(vcurve(1,i,kb),curve(1,i,e),5)
               enddo
            endif
         enddo
         call igop(icurve,wk,'+  ',12*lblock)  ! Sum across all processors
         call  gop(vcurve,wk,'+  ',60*lblock)  ! Sum across all processors

         if (nid.eq.0) then
            kb = 0
            do eg=eb,nemax
               kb  = kb+1

               do i=1,nedge
                  ii = icurve(i,kb)   ! equivalenced to s4
                  if (ii.ne.0) then
                     if (ii.eq.1) cc='C'
                     if (ii.eq.2) cc='s'
                     if (ii.eq.3) cc='m'
                     if (nelgt.lt.1000) then
                        write(10,'(i3,i3,5g14.6,1x,a1)') i,eg,
     $                  (vcurve(k,i,kb),k=1,5),cc
                     elseif (nelgt.lt.1000000) then
                        write(10,'(i2,i6,5g14.6,1x,a1)') i,eg,
     $                  (vcurve(k,i,kb),k=1,5),cc
                     else
                        write(10,'(i2,i10,5g14.6,1x,a1)') i,eg,
     $                  (vcurve(k,i,kb),k=1,5),cc
                     endif
                  endif
               enddo
            enddo
         endif

      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_rea_bc (ifld)

      include 'SIZE'
      include 'TOTAL'

      integer e,eb,eg

      parameter (lblock=500)
      common /scrns/ vbc(5,6,lblock),wk(5*6*lblock)
      common /scruz/ ibc(6,lblock)

      character*1 s4(4)
      character*3 s3
      integer     i4
      equivalence(i4,s4)
      equivalence(s3,s4)

      character*1 chtemp
      save        chtemp
      data        chtemp /' '/   ! For mesh bcs

      nface = 2*ndim

      nlg = nelg(ifld)

      if (ifld.eq.1.and..not.ifflow) then ! NO B.C.'s for this field
         if (nid.eq.0) write(10,*)
     $      ' ***** NO FLUID   BOUNDARY CONDITIONS *****'
         return
      elseif (ifld.eq.1.and.nid.eq.0) then ! NO B.C.'s for this field
         write(10,*) ' *****    FLUID   BOUNDARY CONDITIONS *****'
      elseif (ifld.ge.2.and.nid.eq.0) then ! NO B.C.'s for this field
         write(10,*) ' *****    THERMAL BOUNDARY CONDITIONS *****'
      endif

      do eb=1,nlg,lblock
         nemax = min(eb+lblock-1,nlg)
         call izero(ibc, 6*lblock)
         call rzero(vbc,30*lblock)
         kb = 0
         do eg=eb,nemax
            mid = gllnid(eg)
            e   = gllel (eg)
            kb  = kb+1
            if (mid.eq.nid) then ! fill owning processor
               do i=1,nface
                  i4 = 0
                  call chcopy(s4,cbc(i,e,ifld),3)
                  ibc(i,kb) = i4
                  call copy(vbc(1,i,kb),bc(1,i,e,ifld),5)
               enddo
            endif
         enddo
         call igop(ibc,wk,'+  ', 6*lblock)  ! Sum across all processors
         call  gop(vbc,wk,'+  ',30*lblock)  ! Sum across all processors

         if (nid.eq.0) then
            kb = 0
            do eg=eb,nemax
               kb  = kb+1

               do i=1,nface
                  i4 = ibc(i,kb)   ! equivalenced to s4

c                 chtemp='   '
c                 if (ifld.eq.1 .or. (ifld.eq.2 .and. .not. ifflow))
c    $               chtemp = cbc(i,kb,0)

                  if (nlg.lt.1000) then
                     write(10,'(a1,a3,2i3,5g14.6)')
     $               chtemp,s3,eg,i,(vbc(ii,i,kb),ii=1,5)
                  elseif (nlg.lt.1000000) then
                     write(10,'(a1,a3,i6,5g14.6)')
     $               chtemp,s3,eg,(vbc(ii,i,kb),ii=1,5)
                  else
                     write(10,'(a1,a3,i10,5g14.6)')
     $               chtemp,s3,eg,(vbc(ii,i,kb),ii=1,5)
                  endif
               enddo
            enddo
         endif
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_rea_midside_e(e)

      include 'SIZE'
      include 'TOTAL'

      common /scrns/ x3(27),y3(27),z3(27),xyz(3,3)
      character*1 ccrve(12)
      integer e,edge

      integer e3(3,12)
      save    e3
      data    e3 /  1, 2, 3,    3, 6, 9,    9, 8, 7,    7, 4, 1
     $           , 19,20,21,   21,24,27,   27,26,25,   25,22,19
     $           ,  1,10,19,    3,12,21,    9,18,27,    7,16,25 /

      real len

      call chcopy(ccrve,ccurve(1,e),12)

      call map2reg(x3,3,xm1(1,1,1,e),1)  ! Map to 3x3x3 array
      call map2reg(y3,3,ym1(1,1,1,e),1)
      if (if3d) call map2reg(z3,3,zm1(1,1,1,e),1)



c     Take care of spherical curved face defn
      if (ccurve(5,e).eq.'s') then
         call chcopy(ccrve(1),'ssss',4) ! face 5
         call chcopy(ccrve(5),' ',1)    ! face 5
      endif
      if (ccurve(6,e).eq.'s') then
         call chcopy(ccrve(5),'ssss',4) ! face 6
      endif

      tol   = 1.e-4
      tol2  = tol**2
      nedge = 4 + 8*(ndim-2)

      do i=1,nedge
         if (ccrve(i).eq.' ') then
            do j=1,3
               xyz(1,j)=x3(e3(j,i))
               xyz(2,j)=y3(e3(j,i))
               xyz(3,j)=z3(e3(j,i))
            enddo
            len = 0.
            h   = 0.
            do j=1,ndim
               xmid = .5*(xyz(j,1)+xyz(j,3))
               h    = h   + (xyz(j,2)-xmid)**2
               len  = len + (xyz(j,3)-xyz(j,1))**2
            enddo
            if (h.gt.tol2*len) ccurve(i,e) = 'm'
            if (h.gt.tol2*len) call copy(curve(1,i,e),xyz(1,2),ndim)
         endif
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine hpts
c
c     evaluate velocity, temperature and ps-scalars for list of points
c     (read from file hpts.in) and write the results 
c     into a file (hpts.out)
c     note: read/write on rank0 only 
c
      INCLUDE 'SIZE'
      INCLUDE 'TOTAL'

      parameter(nmax=lpart,nfldmax=ldim+ldimt) 
      parameter(mi=4,mr=1+2*ldim+nfldmax)
      real    rTL(mr,nmax)
      integer iTL(mi,nmax)
      common /itlcb/ iTL
      common /rtlcb/ rTL

      common /outtmp / wrk(lx1,ly1,lz1,lelt,nfldmax)

      integer icalld,npoints
      save    icalld,npoints
      data    icalld  /0/
      data    npoints /0/

      nxyz  = nx1*ny1*nz1
      ntot  = nxyz*nelt

      if(nelgt.ne.nelgv) then
        if(nid.eq.0) write(6,*) 
     &    'ABORT: hpts() no support for nelgt.ne.nelgv!'
        call exitt        
      endif

      if(icalld.eq.0) then
        icalld = 1

        if(nid.eq.0) then
          write(6,*) 'reading hpts.in'
          open(50,file='hpts.in',status='old')
          read(50,*) npoints
          write(6,*) 'found ', npoints, ' points'
          do i = 1,npoints
             read(50,*) (rTL(1+j,i),j=1,ndim)
          enddo
          close(50)
          open(50,file='hpts.out',status='new')
          write(50,'(A)') '# time  vx  vy  [vz]  T  PS1   PS2 ...'
        endif 

        call intpts_setup(-1.0) ! use default tolerance
      endif

      nflds  = nfield + ndim-1 ! number of fields you want to interpolate

      ! pack working array
      call copy(wrk(1,1,1,1,1),vx,ntot)
      call copy(wrk(1,1,1,1,2),vy,ntot)
      if(if3d) call copy(wrk(1,1,1,1,2),vz,ntot)
      do i = 1,nfield-1
         call copy(wrk(1,1,1,1,ndim+i),T(1,1,1,1,i),ntot)
      enddo
      
      ! interpolate
      call intpts(wrk,nflds,iTL,mi,rTL,mr,npoints,.false.)

      ! write interpolation results to file
      if(nid.eq.0) then
        do ip = 1,npoints
           write(50,'(1p20E15.7)') time,
     &      (rTL(1+2*ndim+ifld,ip), ifld=1,nflds)
        enddo
      endif

      return
      end
