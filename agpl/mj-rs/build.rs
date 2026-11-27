use std::{env, fs, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory"));
    for table in ["shanten_jihai.bin", "shanten_suhai.bin", "agari.bin"] {
        let source = format!("src/algo/data/{table}.gz");
        println!("cargo:rerun-if-changed={source}");
        let result = Command::new("gzip")
            .args(["-dc", &source])
            .output()
            .expect("run gzip to unpack the libriichi lookup tables");
        assert!(
            result.status.success(),
            "unpack {source}: {}",
            String::from_utf8_lossy(&result.stderr),
        );
        fs::write(out.join(table), result.stdout).expect("write lookup table into Cargo output");
    }
}
