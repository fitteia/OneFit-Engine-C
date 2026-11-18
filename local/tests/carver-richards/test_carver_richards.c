/* Independent CPMG reference: propagate two intervals using the complex
 * 2x2 Bloch-McConnell matrix, rather than the appendix equations.
 */
#include <complex.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "CarverRichards.h"

static int checks;
static void close_to(double got, double want, double tol, const char *what)
{
    ++checks;
    if (!isfinite(got) || fabs(got-want) > tol*fmax(1.0,fabs(want))) {
        fprintf(stderr,"%s: got %.17g, expected %.17g\n",what,got,want);
        exit(1);
    }
}

static double propagate(double t, double ta, double tb, double ka, double kb, double dw)
{
    double complex a=-1.0/ta-ka+I*dw/2.0;
    double complex d=-1.0/tb-kb-I*dw/2.0;
    double complex h=(a+d)/2.0;
    double complex z=csqrt((a-d)*(a-d)/4.0+ka*kb);
    double complex s=cabs(z)<1e-14 ? t : csinh(z*t)/z;
    double complex c=ccosh(z*t), f=cexp(h*t), e[2][2], p[2][2];
    double complex trace,det,disc;
    int i,j,k;
    e[0][0]=f*(c+s*(a-h)); e[0][1]=f*s*kb;
    e[1][0]=f*s*ka; e[1][1]=f*(c+s*(d-h));
    for (i=0;i<2;++i) for(j=0;j<2;++j) {
        p[i][j]=0;
        for(k=0;k<2;++k) p[i][j]+=conj(e[i][k])*e[k][j];
    }
    trace=p[0][0]+p[1][1]; det=p[0][0]*p[1][1]-p[0][1]*p[1][0];
    disc=csqrt(trace*trace-4.0*det);
    return -log(fmax(cabs((trace+disc)/2.0),cabs((trace-disc)/2.0)))/(2.0*t);
}

static uint32_t state=19721989;
static double uniform(double lo,double hi)
{
    state=1664525*state+1013904223;
    return lo+(hi-lo)*(double)state/4294967296.0;
}

int main(void)
{
    int i;
    for(i=0;i<200;++i) {
        double t=pow(10,uniform(-4,-2)), ta=pow(10,uniform(-2,0));
        double tb=pow(10,uniform(-3,-1)), ka=pow(10,uniform(0,2));
        double kb=pow(10,uniform(1,3)), dw=pow(10,uniform(1,3));
        double r=R2_CR(t,ta,tb,1.0/ka,1.0/kb,0,dw);
        close_to(r,propagate(t,ta,tb,ka,kb,dw),2e-7,"2x2 propagator");
        close_to(R2_CR(t,tb,ta,1.0/kb,1.0/ka,dw,0),r,1e-10,"site swap");
        close_to(T2_CR(t,ta,tb,1.0/ka,1.0/kb,0,dw),1.0/r,1e-12,"T2 reciprocal");
    }
    close_to(R2_CR(.001,.5,.5,.01,.001,0,0),2,1e-9,"no shift, equal rates");
    close_to(R2_CR(.001,.5,.01,INFINITY,INFINITY,0,500),2,1e-9,"no exchange");
    close_to(R2_CR(.001,.1,.1,.01,.01,0,200),
             propagate(.001,.1,.1,100,100,200),1e-9,"rho=0 limit");
    close_to(R2_CR(10,.5,.5,.001,.001,0,0),2,1e-9,"large xi");
    close_to(R2_CR_pb(.001,2,.0038,.01,10000,1000),
             R2_CR(.001,2,.0038,.99/(.01*10000),1e-4,0,1000),1e-12,"detailed balance");
    if(!isnan(R2_CR(0,.5,.1,.1,.1,0,500)) ||
       !isnan(R2_CR_pb(.001,2,.0038,1,10000,1000))) {
        fputs("invalid arguments must return NaN\n",stderr); return 1;
    }
    printf("PASS: %d numerical comparisons and invalid-argument guards\n",checks);
    return 0;
}
