#!/usr/bin/env python3
"""Exercise xmgr.c command construction and failures without installing an engine."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PlotCommands(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="ofe-plot-test-")
        cls.root = Path(cls.scratch.name)
        source = cls.root / "harness.c"
        source.write_text('#include "' + str(ROOT / 'core/onefit-3.1/xmgr.c') + '"\n' + '''
int NT=1, Ma=1, display_flag=0;
char *GRAPH_TYPE="PDF";
char *xs[]={"lin"}, *ys[]={"lin"}, *gp[]={"fit-curves-1"}, *par[]={"fit1.agr-par"};
char **xscale=xs, **yscale=ys, **gph_name=gp, **XMGR_PAR_FILE=par;
double xv[]={0}, xmv[]={1}; double *xm=xv, *xM=xmv, *_T=NULL;
int print_data(char *file,int nfile) { return 0; }
void nrerror(char error_text[]) { fprintf(stderr, "%s\\n", error_text); exit(1); }
int main(int argc,char **argv) {
 if(argc>1 && !strcmp(argv[1],"no-param")) XMGR_PAR_FILE=NULL;
 if(argc>2) display_flag=1;
 xmgr("xmgrace","PDF"); return 0;
}
''')
        cls.binary = cls.root / "harness"
        subprocess.run(["gcc", "-DDEBIAN9", "-ffunction-sections", "-fdata-sections",
                        "-Wl,--gc-sections", str(source), "-o", str(cls.binary), "-lm"], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def run_case(self, args=(), **changes):
        with tempfile.TemporaryDirectory(dir=self.root) as tmp:
            d=Path(tmp); tools=d/'bin'; tools.mkdir()
            for tool in ['plot-go', 'grace', 'cop', 'epstopdf', 'display']:
                failure = 'FAIL_PLOTTER' if tool in ['plot-go', 'grace'] else 'FAIL_CONVERTER' if tool == 'epstopdf' else 'FAIL_DATA' if tool == 'cop' else 'UNUSED'
                f=tools/tool
                f.write_text('#!/bin/sh\n' + ('[ "$1" = -version ] && exit 0\n' if tool=='plot-go' else '')
                    + 'printf "%s\\n" "'+tool+' $*" >> "$TRACE"\n'
                    + 'exit "${'+failure+':-0}"\n')
                f.chmod(0o755)
            (d/'fit-curves-1').write_text('1 2\n')
            env=dict(os.environ, PATH=str(tools)+':/usr/bin:/bin', TRACE=str(d/'trace'), OFE_PLOTTER='')
            env.update(changes)
            p=subprocess.run([str(self.binary),*args],cwd=d,env=env,capture_output=True,text=True,timeout=5)
            return p, (d/'trace').read_text() if (d/'trace').exists() else ''

    def test_normal_and_forced_grace(self):
        p,t=self.run_case(); self.assertEqual(p.returncode,0); self.assertIn('plot-go -settype xydy',t)
        p,t=self.run_case(OFE_PLOTTER='grace'); self.assertEqual(p.returncode,0); self.assertIn('grace -settype xydy',t)

    def test_parameterless_plot_uses_grace_defaults(self):
        for args in [('no-param',), ('no-param','display')]:
            p,t=self.run_case(args)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertIn('grace -nxy fit-curves-1 -settype xydy gnu0.da_',t)
            self.assertIn('-printfile fit-curves-1.eps -saveall fit-curves-1.agr',t)
            self.assertNotIn('epstopdf fit-curves-1.eps -saveall',t)

    # a failed plot is a warning, not a failed fit: the results are written
    def test_failed_plotter_skips_conversion_and_display(self):
        p,t=self.run_case(('param','display'),FAIL_PLOTTER='7')
        self.assertEqual(p.returncode,0,p.stderr); self.assertIn('plot command failed',p.stderr)
        self.assertIn("this block's plot is missing",p.stderr)
        self.assertNotIn('epstopdf',t); self.assertNotIn('display ',t)

    def test_forced_parameterless_plotgo_warns_and_uses_grace(self):
        p,t=self.run_case(('no-param',),OFE_PLOTTER='plot-go')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('requires a parameter file',p.stderr)
        self.assertIn('grace -nxy fit-curves-1',t); self.assertNotIn('plot-go -',t)

    def test_failed_conversion_skips_display(self):
        p,t=self.run_case(('param','display'),FAIL_CONVERTER='9')
        self.assertEqual(p.returncode,0,p.stderr); self.assertIn('plot command failed',p.stderr)
        self.assertNotIn('display ',t)

    def test_failed_data_preparation_skips_the_plot(self):
        p,t=self.run_case(FAIL_DATA='4')
        self.assertEqual(p.returncode,0,p.stderr); self.assertIn('preparation failed',p.stderr)
        self.assertNotIn('plot-go -',t)

if __name__ == '__main__':
    unittest.main()
