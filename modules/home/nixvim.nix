{ config, pkgs, ... }: 
let
	gcc = pkgs.gcc; 
	glibc = pkgs.glibc.dev;
	arch = "x86_64-unknown-linux-gnu";
in {
	# this makes clangd work in nixvim
	home.file.".config/clangd/config.yaml".text = builtins.toJSON {
		CompileFlags = {
  		  Add = [
    		"-I${glibc}/include"
    		"-I${gcc.cc}/include/c++/${gcc.version}"
    		"-I${gcc.cc}/include/c++/${gcc.version}/${arch}"
    		"-I${gcc.cc}/lib/gcc/${arch}/${gcc.version}/include"
  		  ];
		};
	};
	programs.nixvim = {
		enable = true;
		nixpkgs.source = pkgs.path;
		# Same permanent, by-design mismatch as home-manager's own release
		# check (see modules/home/common.nix) — nixvim also only tags
		# against nixos-unstable while this flake pins nixos-26.05.
		version.enableNixpkgsReleaseCheck = false;
		nixpkgs.config = {
			allowUnfree = true;
			allowUnfreePredicate = pkg:
				let
					name = pkgs.lib.getName pkg;
				in
				builtins.elem name [
					"presence.nvim"
					"presence-nvim"
					"vimplugin-presence-nvim"
					"vimplugin-presence.nvim"
				] || (pkgs.lib.hasInfix "presence" name);
		};
		colorscheme = "tokyonight";
		colorschemes.tokyonight = {
			enable = true;
			lazyLoad.enable = true;
		};
		clipboard = {
			register = "unnamedplus";
			providers.wl-copy.enable = true;
		};
		diagnostic.settings = {
				virtual_text = true;
				update_in_insert = false;
				underline = true;
				severity_sort = true;
				float = {
						focused = false;
						style = "minimal";
						border = "rounded";
						source = true;
						header = "";
						prefix = "";
				};
		};
		opts = {
			relativenumber = true;
			number = true;
			mouse = "a";
			swapfile = false;
			autoindent = true;
			copyindent = true;
			cmdheight = 0;
			confirm = true;
			preserveindent = true;
			showmode = false;
			showtabline = 2;
			tabstop = 4;
			shiftwidth = 4;
			termguicolors = true;
			cursorline = true;
			foldcolumn = "auto";
			foldexpr = "0";
			foldenable = true;
			foldlevel = 99;
			foldlevelstart = 99;
			fillchars = "eob: ,fold: ,foldopen:,foldsep: ,foldclose:";
			undofile = true;
		};
		globals = {
			mapleader = " ";
			maplocalleader = ",";
		};
		keymaps = [
			{
				action = "<cmd>lua vim.lsp.buf.definition()<CR>";
				key = "gd";
				mode = [ "n" "v" ];
				options = {
					desc = "Go to definition";
				};
			}
		];
		plugins = {
			lsp = {
				enable = true;
				servers = {
					pyright.enable = true;
					diagnosticls.enable = true;
					nixd.enable = true;
					emmet_ls.enable = true;
					html.enable = true;
					cssls.enable = true;
					jdtls.enable = true;
					clangd.enable = true;
				};
			};
			lz-n.enable = true;
			lsp-signature.enable = true;
			nvim-autopairs = {
				enable = true;
				luaConfig.post = ''
      				  local npairs = require "nvim-autopairs"
      				  local Rule = require "nvim-autopairs.rule"
      				  local cond = require "nvim-autopairs.conds"

      				  local brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } }
      				  npairs.add_rules {
        				-- Rule for a pair with left-side ' ' and right side ' '
        				Rule(" ", " ")
          				  -- Pair will only occur if the conditional function returns true
          				  :with_pair(function(opts)
            				-- We are checking if we are inserting a space in (), [], or {}
            				local pair = opts.line:sub(opts.col - 1, opts.col)
            				return vim.tbl_contains({
              				  brackets[1][1] .. brackets[1][2],
              				  brackets[2][1] .. brackets[2][2],
              				  brackets[3][1] .. brackets[3][2],
            				}, pair)
          				  end)
          				  :with_move(cond.none())
          				  :with_cr(cond.none())
          				  -- We only want to delete the pair of spaces when the cursor is as such: ( | )
          				  :with_del(
            				function(opts)
              				  local col = vim.api.nvim_win_get_cursor(0)[2]
              				  local context = opts.line:sub(col - 1, col + 2)
              				  return vim.tbl_contains({
                				brackets[1][1] .. "  " .. brackets[1][2],
                				brackets[2][1] .. "  " .. brackets[2][2],
                				brackets[3][1] .. "  " .. brackets[3][2],
              				  }, context)
            				end
          				  ),
      				  }
      				  -- For each pair of brackets we will add another rule
      				  for _, bracket in pairs(brackets) do
        				npairs.add_rules {
          				  -- Each of these rules is for a pair with left-side '( ' and right-side ' )' for each bracket type
          				  Rule(bracket[1] .. " ", " " .. bracket[2])
            				:with_pair(cond.none())
            				:with_move(function(opts) return opts.char == bracket[2] end)
            				:with_del(cond.none())
            				:use_key(bracket[2])
            				-- Removes the trailing whitespace that can occur without this
            				:replace_map_cr(
              				  function(_) return "<C-c>2xi<CR><C-c>O" end
            				),
        				}
      				  end
				'';
			};
			vim-bbye.enable = true;
			blink-cmp = {
				enable = true;
				settings = {
					keymap = {
						preset = "super-tab";
					};
				};
			};
			inc-rename.enable = true;
			presence.enable = true;
			noice = {
				enable = true;
				settings = {
					presets.inc_rename = true;
				};
			};
			ts-autotag.enable = true;
			luasnip = {
				enable = true;
				# filetype_extend ?
			};
			friendly-snippets.enable = true;
			gitsigns.enable = true;
			which-key = {
				enable = true;
				settings.icons.group = "";
				settings.spec = [
					{
						__unkeyed-1 = "<leader>e";
						__unkeyed-2 = ":Neotree toggle<CR>";
						desc = "Toggle explorer";
						icon = " ";
					}
					{
						__unkeyed-1 = "<leader>w";
						__unkeyed-2 = ":w<CR>";
						desc = "Save";
						icon = "󰆓 ";
					}
					{
						__unkeyed-1 = "<leader>q";
						__unkeyed-2 = ":q<CR>";
						desc = "Exit";
					}
					{
						__unkeyed-1 = "<leader>o";
						__unkeyed-2 = {
							__raw = ''
								function()
								    if vim.bo.filetype == "neo-tree" then
								      vim.cmd.wincmd "p"
								    else
								      vim.cmd.Neotree "focus"
								    end
								end	
							'';
						};
						desc = "Toggle explorer focus";
					}
					{
						__unkeyed-1 = "<leader>n";
						__unkeyed-2 = ":ene<CR>";
						icon = " ";
						desc = "New file";
					}
					{
						__unkeyed = "<leader>b";
						group = "Buffer";
						icon = "󰓩 ";
					}
					{
						__unkeyed-1 = "<leader>bp";
						__unkeyed-2 = ":BufferLinePickClose<CR>";
						icon = " ";
						desc = "Pick to close";
					}
					{
						__unkeyed-1 = "<leader>bC";
						__unkeyed-2 = ":BufferLineCloseOthers<CR>";
						icon = " ";
						desc = "Close other buffers";
					}
					{
						__unkeyed-1 = "<leader>bc";
						__unkeyed-2 = ":Bdelete<CR>";
						icon = " ";
						desc = "Close current buffer";
					}
					{
						__unkeyed-1 = "<leader>b<";
						__unkeyed-2 = ":BufferLineMovePrev<CR>";
						icon = " ";
						desc = "Move buffer left";
					}
					{
						__unkeyed-1 = "<leader>b>";
						__unkeyed-2 = ":BufferLineMoveNext<CR>";
						icon = " ";
						desc = "Move buffer right";
					}
					{
						__unkeyed-1 = "<leader>h";
						__unkeyed-2 = ":Dashboard<CR>";
						icon = " ";
						desc = "Home";
					}
					{
						__unkeyed = "<leader>f";
						icon = " ";
						group = "Telescope";
					}
					{
						__unkeyed-1 = "<leader>ff";
						__unkeyed-2 = ":Telescope find_files<CR>";
						icon = "󰈞 ";
						desc = "Find file";
					}
					{
						__unkeyed-1 = "<leader>f/";
						__unkeyed-2 = ":Telescope current_buffer_fuzzy_find<CR>";
						icon = "󰬴 ";
						desc = "Find in buffer";
					}
					{
						__unkeyed-1 = "<leader>fw";
						__unkeyed-2 = ":Telescope live_grep<CR>";
						icon = " ";
						desc = "Find word";
					}
					{
						__unkeyed-1 = "<leader>fb";
						__unkeyed-2 = ":Telescope buffers<CR>";
						icon = " ";
						desc = "Find buffer";
					}
					{
						__unkeyed-1 = "<leader>fc";
						__unkeyed-2 = ":Telescope colorscheme<CR>";
						icon = " ";
						desc = "Find colorscheme";
					}
					{
						__unkeyed-1 = "<leader>fs";
						__unkeyed-2 = ":AutoSession search<CR>";
						icon = "󱈆 ";
						desc = "Search sessions";
					}
					{
						__unkeyed-1 = "<leader>l";
						icon = " ";
						group = "Language Tools";
					}
					{
						__unkeyed-1 = "<leader>ld";
						__unkeyed-2 = {
								__raw = ''
										function() vim.diagnostic.open_float() end
								'';
						};
						icon = " ";
						desc = "Hover diagnostics";
					}
					{
						__unkeyed-1 = "<leader>lr";
						__unkeyed-2 = ":IncRename ";
						icon = " ";
						desc = "Rename";
					}
					{
						__unkeyed-1 = "<leader>ls";
						__unkeyed-2 = ":AerialToggle<CR>";
						icon = "󰅳 ";
						desc = "Symbols";
					}
					{
						__unkeyed-1 = "<leader>lf";
						__unkeyed-2 = ":FormatToggle<CR>";
						icon = " ";
						desc = "Toggle formatting";
					}
					{
						__unkeyed-1 = "<leader>t";
						icon = " ";
						group = "Terminal";
					}
					{
						__unkeyed-1 = "<leader>tf";
						__unkeyed-2 = ":ToggleTerm direction=float <CR>";
						icon = "󱂬 ";
						desc = "Open float";
					}
					{
						__unkeyed-1 = "<leader>th";
						__unkeyed-2 = ":ToggleTerm size=10 direction=horizontal<CR>";
						icon = " ";
						desc = "Open horizontal";
					}
					{
						__unkeyed-1 = "<leader>tv";
						__unkeyed-2 = ":ToggleTerm size=80 direction=vertical<CR>";
						icon = " ";
						desc = "Open vertical";
					}
				];
			};
			treesitter = {
				enable = true;
				settings = {
						highlight.enable = true;
						# indent.enable = true;
						# incremental_selection.enable = true;
				};
				grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
					bash
					fish
					nix
					python
					java
					javadoc
					javascript
					typescript
					cpp
					make
					json
					yaml
					xml
					lua
					toml
					ssh_config
					markdown
					regex
					vim
					vimdoc
					regex
					yuck
				];
			};
			telescope = {
				enable = true;
				lazyLoad = {
					enable = false;
					settings = {
						cmd = "Telescope";
						keys = [
							"<leader>fb"
							"<leader>fc"
							"<leader>ff"
							"<leader>fs"
							"<leader>fw"
							"<leader>f/"
						];
					};
				};
				settings.defaults.mappings = {
      					i = {
        					"<C-j>" = {
          						__raw = "require('telescope.actions').move_selection_next";
        					};
        					"<C-k>" = {
          						__raw = "require('telescope.actions').move_selection_previous";
        					};
        					"<C-h>" = {
								__raw = "require('telescope.actions').preview_scrolling_left";
        					};
        					"<C-l>" = {
								__raw = "require('telescope.actions').preview_scrolling_right";
        					};
      					};
				};
			};
			smear-cursor.enable = true;
			smear-cursor.settings.distance_stop_animating = 0.1;
			lsp-format.enable = true;
			none-ls = {
				enable = true;
				sources.formatting = {
					prettierd.enable = true;
					rustywind.enable = true;
					clang_format = {
						enable = true;
						settings.extra_args = [ "--tab-width" "4" ];
					};
					nixfmt = {
						enable = false;
					    settings.extra_args = [ "--tab-width" "4" ]; # that does not work :(, see issue no. 57 
					};
					black = {
						enable = true;
						settings.extra_args = [ "--tab-width" "4" ];
					};
					xmllint.enable = true;
				};
			};
			aerial = {
					enable = true;
					lazyLoad = {
						enable = true;
						settings = {
							cmd = [ "AerialOpen" "AerialToggle" ];
							keys = [ "<leader>ls" ];
						};
					};
					settings = {
						attach_mode = "global";
						filter_kind = false;
						layout.min_width = 28;
						show_guides = true;
						guides = {
        						mid_item = "├ ";
        						last_item = "└ ";
        						nested_top = "│ ";
        						whitespace = "  ";
      					};
      					backends = [
  							"treesitter"
   							"lsp"
							"markdown"
							"man"
						];
					};
			};
			lualine = {
				enable = true;
				settings = {
  						options = {
    						disabled_filetypes = {
      						  __unkeyed-1 = "alpha";
      						  __unkeyed-2 = "neo-tree";
      						  statusline = [
        						"dap-repl"
      						  ];
    						};
    						globalstatus = true;
  						  };
  						  sections = {
    						lualine_a = [
      						  "mode"
    						];
    						lualine_b = [
      						  "branch"
    						];
    						lualine_c = [
      						  "filename"
      						  "diff"
    						];
    						lualine_x = [
      						  "diagnostics"
      						  {
        						__unkeyed-1 = {
          						  __raw = ''
            						function()
                						local msg = ""
                						local buf_ft = vim.api.nvim_buf_get_option(0, 'filetype')
                						local clients = vim.lsp.get_active_clients()
                						if next(clients) == nil then
                    						return msg
                						end
                						for _, client in ipairs(clients) do
                    						local filetypes = client.config.filetypes
                    						if filetypes and vim.fn.index(filetypes, buf_ft) ~= -1 then
                        						return client.name
                    						end
                						end
                						return msg
            						end
          						  '';
        						};
        						color = {
          						  fg = "#ffffff";
        						};
        						icon = "";
      						  }
      						  "encoding"
      						  "fileformat"
      						  "filetype"
    						];
    						lualine_y = [
      						  {
        						__unkeyed-1 = "aerial";
        						colored = true;
        						cond = {
          						  __raw = ''
            						function()
              						  local buf_size_limit = 1024 * 1024
              						  if vim.api.nvim_buf_get_offset(0, vim.api.nvim_buf_line_count(0)) > buf_size_limit then
                						return false
              						  end
            						
              						  return true
            						end
          						  '';
        						};
        						dense = false;
        						dense_sep = ".";
        						depth = {
          						  __raw = "nil";
        						};
        						sep = " ) ";
      						  }
    						];
    						lualine_z = [
      						  {
        						__unkeyed-1 = "location";
      						  }
    						];
  						  };
						};
			};
			neo-tree = {
				enable = true;
				settings = {
					close_if_last_window = true;
					commands = {
						system_open = config.lib.nixvim.mkRaw "function(state) vim.ui.open(state.tree:get_node():get_id()) end";
						parent_or_close = config.lib.nixvim.mkRaw ''
						function(state)
						  local node = state.tree:get_node()
						  if node:has_children() and node:is_expanded() then
						    state.commands.toggle_node(state)
						  else
						    require("neo-tree.ui.renderer").focus_node(state, node:get_parent_id())
						  end
						end
						'';
						child_or_open = config.lib.nixvim.mkRaw ''
						function(state)
						  local node = state.tree:get_node()
						  if node:has_children() then
						    if not node:is_expanded() then -- if unexpanded, expand
						      state.commands.toggle_node(state)
						    else -- if expanded and has children, seleect the next child
						      if node.type == "file" then
							state.commands.open(state)
						      else
							require("neo-tree.ui.renderer").focus_node(state, node:get_child_ids()[1])
						      end
						    end
						  else -- if has no children
						    state.commands.open(state)
						  end
						end	
						'';
					};
					window.mappings = {
						"<S-CR>" = "system_open";
						"[b" = "prev_source";
						"]b" = "next_source";
						O = "system_open";
						h = "parent_or_close";
						l = "child_or_open";
					};
				};
			};
			dashboard = {
				enable = true;
				lazyLoad = {
					enable = false;
					settings = {
						cmd = "Dashboard";
						keys = [ "<leader>h" ];
					};
				};
				settings = {
  		  		  config = {
    				header = [
    				  ""
    				  ""
    				  ""
      		  		  "███╗   ██╗██╗██╗  ██╗██╗   ██╗██╗███╗   ███╗"
      		  		  "████╗  ██║██║╚██╗██╔╝██║   ██║██║████╗ ████║"
      		  		  "██╔██╗ ██║██║ ╚███╔╝ ██║   ██║██║██╔████╔██║"
      		  		  "██║╚██╗██║██║ ██╔██╗ ╚██╗ ██╔╝██║██║╚██╔╝██║"
      		  		  "██║ ╚████║██║██╔╝ ██╗ ╚████╔╝ ██║██║ ╚═╝ ██║"
      		  		  "╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝     ╚═╝"
    				  ""
    				  ""
    				];
					center = [
						{
							desc = "Search sessions";
							action = "AutoSession search";
							desc_hl = "String";
							icon = "󱈆 ";
							icon_hl = "Title";
							key = "s";
							key_format = " [%s]";
							key_hl = "Number";
							keymap = "SPC f s";
						}
						{
							desc = "Search files";
							action = "Telescope find_files";
							desc_hl = "String";
							icon = "󰱼 ";
							icon_hl = "Title";
							key = "f";
							key_format = " [%s]";
							key_hl = "Number";
							keymap = "SPC f f";
						}
						{
							desc = "New file";
							action = "ene";
							desc_hl = "String";
							icon = " ";
							icon_hl = "Title";
							key = "n";
							key_format = " [%s]";
							key_hl = "Number";
							keymap = "SPC n";
						}
						{
							desc = "Quit Neovim";
							action = "qa";
							desc_hl = "String";
							icon = "󰈆 ";
							icon_hl = "Title";
							key = "q";
							key_format = " [%s]";
							key_hl = "Number";
							keymap = "SPC q";
						}
					];
  		  		  	disable_move = true;
  		  		  	change_to_vcs_root = true;
  		  		  };
  		  		  theme = "doom";
				};
			};
			web-devicons.enable = true;
			auto-save.enable = true;
			toggleterm = {
				enable = true;
				lazyLoad = {
					enable = true;
					settings.cmd = "ToggleTerm";
					settings.keys = [
						"<leader>tf"
						"<leader>tv"
						"<leader>th"
					];
				};
				settings.shell = "fish";
			};
			bufferline = {
				enable = true;
				settings = {
					highlights = {
						fill.bg = "#222436";
					};
					options = {
						show_buffer_close_icons = true;
						show_buffer_icons = true;
						show_close_icon = true;
						show_tab_indicators = true;
						indicator = {
							style = "underline";
						};
						diagnostics = "nvim_lsp";
						offsets = [
							{
							  filetype = "neo-tree";
							  highlight = "Directory";
							  text = "File Explorer";
							  text_align = "center";
							}
						];
					};
				};
			};
			colorizer.enable = true;
			illuminate = {
				enable = true;
				settings.filetypes_denylist = [
					"neo-tree"
					"TelescopePrompt"
					"dashboard"
					"noice"
					"checkhealth"
				];
			};
			nvim-ufo = {
				enable = true;
				luaConfig.post = ''
					local capabilities = vim.lsp.protocol.make_client_capabilities()
					capabilities.textDocument.foldingRange = {
    					dynamicRegistration = false,
    					lineFoldingOnly = true
					}
					local language_servers = vim.lsp.get_clients() -- or list servers manually like {'gopls', 'clangd'}
					for _, ls in ipairs(language_servers) do
    					require('lspconfig')[ls].setup({
        					capabilities = capabilities
        					-- you can add other fields for setting up lsp server in this table
    					})
					end
				'';
				settings = {
					fold_virt_text_handler.__raw = ''
    					function(virtText, lnum, endLnum, width, truncate)
      		  		  	  local newVirtText = {}
      		  		  	  local suffix = (' 󰁂 %d '):format(endLnum - lnum)
      		  		  	  local sufWidth = vim.fn.strdisplaywidth(suffix)
      		  		  	  local targetWidth = width - sufWidth
      		  		  	  local curWidth = 0
      		  		  	  for _, chunk in ipairs(virtText) do
        					local chunkText = chunk[1]
        					local chunkWidth = vim.fn.strdisplaywidth(chunkText)
        					if targetWidth > curWidth + chunkWidth then
          		  		  	  table.insert(newVirtText, chunk)
        					else
          		  		  	  chunkText = truncate(chunkText, targetWidth - curWidth)
          		  		  	  local hlGroup = chunk[2]
          		  		  	  table.insert(newVirtText, {chunkText, hlGroup})
          		  		  	  chunkWidth = vim.fn.strdisplaywidth(chunkText)
          		  		  	  -- str width returned from truncate() may less than 2nd argument, need padding
          		  		  	  if curWidth + chunkWidth < targetWidth then
            					suffix = suffix .. (' '):rep(targetWidth - curWidth - chunkWidth)
          		  		  	  end
          		  		  	  break
        					end
        					curWidth = curWidth + chunkWidth
      		  		  	  end
      		  		  	  table.insert(newVirtText, {suffix, 'MoreMsg'})
      		  		  	  return newVirtText
    					end
  		  		  	  '';
  					preview.win_config = {
  						border = "rounded";
  						maxheight = 20;
  						winblend = 12;
  						winhighlight = "Normal:Normal";
  					};
				};
			};
			statuscol = {
				enable = true;
				settings = {
					setopt = true;
					relculright = true;
					ft_ignore = [
						"neo-tree"
						"dashboard"
						"TelescopePrompt"
						"checkhealth"
					];
					segments = [
						{
							click = "v:lua.ScSa";
							text = [ { __raw = "require('statuscol.builtin').foldfunc"; } ];
						}
						{
							click = "v:lua.ScFa";
							text = [ "%s" ];
						}
						{
							click = "v:lua.ScLa";
							condition = [
								true
								{
									__raw = "require('statuscol.builtin').not_empty";
								}
							];
							text = [
								{
									__raw = "require('statuscol.builtin').lnumfunc";
								}
								" "
							];
						}
					];
				};
			};
			jupytext.enable = true;
			plantuml-syntax.enable = true;
			spider = {
				enable = true;
				keymaps.motions = {
  		  		  	  b = "b";
  		  		  	  e = "e";
  		  		  	  ge = "ge";
  		  		  	  w = "w";
	    		};
			};
			auto-session = {
				enable = true;
				settings = {
					enabled = true;
					auto_create = true;
					auto_restore = true;
					auto_restore_last_session = false;
					auto_save = true;
					session_lens.previewer = null;
				};
			};
		};
	};
}
