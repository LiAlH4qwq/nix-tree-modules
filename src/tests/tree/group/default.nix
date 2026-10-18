{ here, lib, ... }: {
  here.switch = {
    generate = true;
    default = true;
    premise = {
      any = [
        [
          "here"
          "c1"
        ]
        [
          "here"
          "c2"
        ]
      ];
    };
  };
  here.options.gmark = lib.mkOption {
    type = lib.types.str;
    default = "off";
  };
  here.apply.liuxu.app.group.gmark = "on";
}
