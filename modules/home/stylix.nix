{ pkgs, ... }: {
	stylix = {
		enable = false;
		base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyodark.yaml";
		fonts = {
    		serif = {
      			package = pkgs.jetbrains-mono;
      			name = "JetBrainsMono Nerd Font";
    		};

    		sansSerif = {
      			package = pkgs.jetbrains-mono;
      			name = "JetBrainsMono Nerd Font";
    		};

    		monospace = {
      			package = pkgs.jetbrains-mono;
      			name = "JetBrainsMono Nerd Font Mono";
    		};

    		emoji = {
      	  		package = pkgs.noto-fonts-color-emoji;
      	  		name = "Noto Color Emoji";
    		};
    		sizes.terminal = 10.5;
    		sizes.applications = 11;
		};
		targets = {
			librewolf.profileNames = [ "my-profile" ];
		};
	};
}
