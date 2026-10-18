{ here, lib, ... }: {
  here.switch = {
    generate = true;
    default = true;
    premise = [ "base" ];
  };
  here.options.marker = lib.mkOption {
    type = lib.types.str;
    default = "off";
  };
  here.apply.liuxu.app.x.marker = "on";
}
