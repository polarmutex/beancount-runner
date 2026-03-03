fn main() {
    prost_build::Config::new()
        .compile_protos(
            &[
                "../../proto/common.proto",
                "../../proto/directives.proto",
                "../../proto/messages.proto",
            ],
            &["../../proto/"],
        )
        .unwrap();
}
