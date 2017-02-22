﻿-- Skill Profile class template for the Skill Manager

-- forward declaration 
local sm_action = class('sm_action')
local sm_skillset = class('sm_skillset')

local sm_skill_profile = class('sm_skill_profile')
sm_skill_profile.filepath = ""
sm_skill_profile.filename = ""
sm_skill_profile.modulefunctions = nil 	-- private store addon functions
sm_skill_profile.context = {}					-- private addons can use their own custom variables or functions
sm_skill_profile.name = ""						-- Custom profile name that is displayed in the dropdown menu
sm_skill_profile.mainmenucode = ""		-- UI Code of the SM Profile that is rendered in the Main Menu
sm_skill_profile.smcode = ""					-- UI Code that is rendered in the SM window above the skills
sm_skill_profile.smskilllistcode = ""		-- UI Code to present, manage and edit the skills
sm_skill_profile.profession = 1				-- The Class or Profession the skillprofile is made for
sm_skill_profile.skillsets = {}					-- Holds all "sets" of skills  (- grouped together skills by weapontype or transformation or similiar)
sm_skill_profile.texturepath = GetStartupPath() .. "\\GUI\\UI_Textures"
sm_skill_profile.texturecache = GetLuaModsPath() .. "\\SkillManager\\Cache"
sm_skill_profile.actionlist = {}				-- The priority list used for casting, holding all skills / combos in order 1 - n
sm_skill_profile.currentskills = {}			-- Holds a copy of the "live data" of the player skills
sm_skill_profile.cooldownlist = {}			-- Another internal list to know which skills were on cd
sm_skill_profile.skilldata = {}				-- Additional Skill Data from the API


-- These 2 needs to be set before the profile can be loaded / saved. Pass the 3rd arg for private addon handling
function sm_skill_profile:initialize(filepath, filename, modulefunctions, customcontext, profession)
	self.filepath = filepath
	self.filename = filename
	self.modulefunctions = modulefunctions
	self.context = customcontext or {}	
	self.profession = profession or SkillManager:GetPlayerProfession()
	self.activeskillrange = 154
end

-- Saving this Profile
function sm_skill_profile:Save()
	if ( self.filepath ~= "" and self.filename ~= "" ) then
		if ( FolderExists(self.filepath) ) then			
			self:PreSave()
			local copy = {}
			copy.name = self.name
			copy.mainmenucode = self.mainmenucode
			copy.smcode = self.smcode
			copy.smskilllistcode = self.smskilllistcode
			copy.profession = self.profession			
			-- Saving the essential data for actionlist
			copy.actionlist = {}
			local idx = 1
			for orderid,v in pairs(self.actionlist) do 							
				copy.actionlist[idx] = v:Save()
				idx = idx + 1 
			end
			-- Saving the essential data for skillsets
			copy.skillsets = {}
			for i,v in pairs(self.skillsets) do 							
				copy.skillsets[i] = { id = v.id, name = v.name or "", activateskillid = v.activateskillid, deactivateskillid = v.deactivateskillid}
				copy.skillsets[i].skills = {}
				for id,s in pairs(v.skills) do
					copy.skillsets[i].skills[id] = { slot = s.slot , minrange = s.minrange or 0, maxrange = s.maxrange or 0, radius = s.radius or 0,  power = s.power or 0, flip_level = s.flip_level or 0}
				end				
			end	
			
			FileSave(self.filepath.."\\"..self.filename..".sm", copy)
			self:AfterSave()
			d("[SkillManager::SkillProfile] - Saved Profile : "..self.filename..".sm")
		else
			ml_error("[SkillManager::SkillProfile] - Could not save Profile, invalid Profile folder: "..self.filepath)
		end		
	else
		ml_error("[SkillManager::SkillProfile] - Could not save Profile, invalid name or folderpath!")
	end
end

-- Loading this Profile (Handles also private addon case)
function sm_skill_profile:Load()
	if ( self.filepath ~= "" and self.filename ~= "" and FolderExists(self.filepath)) then
		-- Handle private addon profile & normal public one
		local data
		if ( FileExists(self.filepath.."\\"..self.filename..".sm" )) then
			-- Developer case, he has the original profile
			 data = FileLoad(self.filepath.."\\"..self.filename..".sm")
		else
			-- User case, he has only the .paf file
			if ( self.modulefunctions ) then			
				local files = self.modulefunctions.GetModuleFiles("data")		
				if(table.size(files)>0) then
					for _,filedata in pairs(files) do
						if( self.filename..".sm" == filedata.f) then
							local fileString = spvp.modulefunctions.ReadModuleFile(filedata)
							if(fileString) then						
								local fileFunction, errorMessage = loadstring(fileString)
								if (fileFunction) then
									data = fileFunction()					
								end
							end
							break
						end
					end
				else
					ml_error("[SkillManager::SkillProfile] - Error, no 'data' subfolder or no SM Profiles in that folder found!")
				end
			else
				ml_error("[SkillManager::SkillProfile] - Error, no PrivateModuleFunctions found! ")
			end
		end
		
		-- Check if loaded profile is valid
		if ( table.valid(data)) then
			-- reset the lists, we are only working in the same "instance" , so "classes" would get loaded twice ;)
			self.actionlist = {} 
			self.skillsets = {}
			for k, v in pairs(data) do
				if ( k ~= "filepath" and k ~= "filename" ) then
					-- Fill ActionList
					if ( k == "actionlist" and table.size(v) > 0 ) then
						-- creating action instances 
						for orderid,actiondata in pairs(v) do							
							local action = sm_action:new(actiondata)
							--[[local extradata = self:GetSkillDataByID( id )
							if ( extradata ) then
								for l,d in pairs(extradata) do
									action[l] = d
								end							
							end]]
							self.actionlist[orderid] = action
						end
					
					-- Fill Skillsets
					elseif ( k == "skillsets" and table.size(v) > 0 ) then
						for id,setdata in pairs(v) do							
							if ( setdata.skills ) then
								for skillid, _ in pairs (setdata.skills) do
									local extradata = self:GetSkillDataByID( skillid )
									if ( extradata ) then
										for key,d in pairs(extradata) do
											setdata.skills[skillid][key] = d
										end
									end
								end
							end
							local skillset = sm_skillset:new(setdata)							
							self.skillsets[id] = skillset
						end
					
					else
						self[k] = v
					end
				end
			end
			local name = self.name or self.filename
			d("[SkillManager::SkillProfile] - Successfully Loaded Profile: "..name)
			return self
		else
			ml_error("[SkillManager::SkillProfile] - Error loading Profile: "..tostring(self.filepath).." // "..tostring(self.filename)..".sm")
		end
	else
		ml_error("[SkillManager::SkillProfile] - Could not load Profile, invalid filename or folderpath: "..tostring(self.filepath).." // "..tostring(self.filename)..".sm")
	end
end

-- Renders Custom Profile UI Elements into the Main Menu of the Bot
function sm_skill_profile:RenderMainMenu()
	if ( self.mainmenucode ) then
		if ( self.menucodechanged or not self.menucodefunc ) then
			local execstring = 'return function(self, context) '..self.mainmenucode..' end'
			local func = loadstring(execstring)
			if ( func ) then
				func()(self, self.context)
				self.menucodechanged = nil
				self.menucodefunc = func	
			else				
				ml_error("SkillManagerProfile::RenderMainMenu() compilation error in ".. tostring(self.name ~= "" and self.name or self.filename ))
				assert(loadstring(execstring)) -- print out the actual error
			end
		else
			--executing the already loaded function
			self.menucodefunc()(self, context)
		end
	end
end


-- TODO: MOVE ALL INTO SEPERATE ADDON!
-- GW2 Specific Code starts here:
sm_skill_profile.slotnames = { 
	[1] = GetString(" W1"),
	[2] = GetString(" W2"),
	[3] = GetString(" W3"),
	[4] = GetString(" W4"),
	[5] = GetString(" W5"),
	[6] = GetString("Heal"),
	[7] = GetString("Util1"),
	[8] = GetString("Util2"),
	[9] = GetString("Util3"),
	[10] = GetString("Elite"),
	[11] = GetString("??1"),
	[12] = GetString("??2"),
	[13] = GetString(" F1"),
	[14] = GetString(" F2"),
	[15] = GetString(" F3"),
	[16] = GetString(" F4"),
	[17] = GetString(" F5"),
	[18] = GetString("S1"),
}

sm_skill_profile.professions = { 
	[1] = GetString("Guardian"), 
	[2] = GetString("Warrior"), 
	[3] = GetString("Engineer"), 
	[4] = GetString("Ranger"), 
	[5] = GetString("Thief"), 
	[6] = GetString("Elementalist"), 
	[7] = GetString("Mesmer"), 
	[8] = GetString("Necromancer"), 
	[9] = GetString("Revenant"), 
	}
	
-- Resets all kinds of "modified" toggle vars, after saving. Enforces "reloading" of all codeeditor text.
function sm_skill_profile:PreSave()
	self.actioneditoropen = nil
	self.modified = nil
	self.menucodechanging = nil
	self.selectedskill = nil
	self.selectedskillset = nil
	self.lasttick = nil
	self.context = nil
	self.dragid = nil
	self.dropid = nil
	self.dropidhover = nil
	self.activeskillrange = nil
end
function sm_skill_profile:AfterSave()
	self.menucodechanged = true
	self.actioneditoropen = true
	self.activeskillrange = 154
end

-- Renders the profile template into the SM "main" window
function sm_skill_profile:Render()
	
	if ( GUI:TreeNode(GetString("Profile Editor")) ) then
		GUI:PushItemWidth(180)
		GUI:AlignFirstTextHeightToWidgets()
		GUI:Text(GetString("Custom Name:")) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Give the Profile a custom name (The filename will not change!).")) end
		GUI:SameLine(120)
		local changed 	
		self.name,changed = GUI:InputText("##smp1",self.name or self.filename)
		if ( changed ) then self.modified = true end
		
		GUI:AlignFirstTextHeightToWidgets()
		GUI:Text(GetString("Profession:")) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("The Profession this Profile is for.")) end
		GUI:SameLine(120)
		self.profession, changed = GUI:Combo("##smp2",self.profession, self.professions)
		if ( changed ) then self.modified = true end
		GUI:PopItemWidth()
		GUI:Separator()
-- DEBUG 

		GUI:Text("DEBUG: activeskillrange  : "..tostring(self.activeskillrange))
		GUI:Text("DEBUG: maxattackrange  : "..tostring(ml_global_information.AttackRange))

-- Main Menu UI CodeEditor
		local _,maxy = GUI:GetContentRegionAvail()
		GUI:SetNextTreeNodeOpened(false,GUI.SetCond_Once)
		if ( GUI:TreeNode(GetString("Main Menu UI CodeEditor")) ) then			
			local x,y = GUI:GetWindowSize()
			if ( y < 700 ) then y = 700 end
			GUI:SetWindowSize(650,y)
			if ( GUI:IsItemHovered() ) then GUI:SetTooltip( "CodeEditor for SkillProfile UI Elements shown in the Main Menu Window" ) end
			local maxx,_ = GUI:GetContentRegionAvail()
			local changed = false
			self.mainmenucode, changed = GUI:InputTextEditor( "##smmainmenueditor", self.mainmenucode, maxx, math.max(maxy/2,300) , GUI.InputTextFlags_AllowTabInput)
			if ( changed ) then self.menucodechanging = true self.modified = true end
			if ( self.menucodechanging ) then
				GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
				GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
				GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
				GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
				if ( GUI:Button(GetString("Save Changes"),maxx,20) ) then						
					self:Save()					
				end				
				GUI:PopStyleColor(4)
			end
			GUI:PushItemWidth(600)
			GUI:Dummy(600,1)
			GUI:PopItemWidth()
			GUI:TreePop()
		else
			local x,y = GUI:GetWindowSize()
			if ( y < 400 ) then y = 400 end
			GUI:SetWindowSize(310,y) -- locl width
		end
		
		GUI:Separator()

-- Skill List
		GUI:Text(GetString("Action List:"))
		if ( GUI:IsItemHovered() ) then GUI:SetTooltip(GetString("Click and drag actions to switch places. Action List is a Priority List!")) end
		local wx,wy = GUI:GetContentRegionAvail()
		if ( wy < 200 ) then wy = 200 end -- minumum of 200 y size
		GUI:BeginChild("##actionlistgrp",wx-10,wy)
		local imgsize = 25
		local hoveringaction
		GUI:PushStyleVar(GUI.StyleVar_ItemSpacing, 0, 4)
		GUI:PushStyleVar(GUI.StyleVar_FramePadding, 0, 0)
		-- CanCast() ->Evaluate is using 2 args, player and target which are saved on the profile
		if (not self.pp_castinfo) then self.pp_castinfo = Player.castinfo end
		if (not self.player) then self.player = Player end
		if (not self.target) then self.target = Player:GetTarget() end
		if (not self.sets) then self.sets = self:GetCurrentSkillSets() end
		
		for k,v in pairs(self.actionlist) do
			local size = imgsize
			local skills = {}
			local skillsets = {}
			for q,w in pairs(v.sequence) do
				skills[q], skillsets[q] = self:GetSkill(w.id)
			end
			local texture = skills[1] ~= nil and self.texturecache.."\\default.png" or self.texturecache.."\\blank.png"			
			local cd = 0
			local colorset
			local labelx,labely = GUI:GetCursorScreenPos()
			local label
			local recx,recy,recw,rech
			
			if ( self.selectedactionid == k ) then	
				size = 45							
				GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
				GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
				GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
				GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
				colorset = true
				labelx = labelx + 55
				labely = labely + size/3
				label = v.name
				
				for q,s in pairs(v.sequence) do
					if ( not skills[q] ) then
						if ( s.id > 0 ) then
							label = "[Missing Skill Data ID: "..tostring(s.id)	
						else
							label = "[Empty Action]"
						end
					end
				end
				
			elseif ( #skills > 0 ) then				
				local currenltycast				
				for q,s in pairs(skills) do
					if ( self.currentaction == k and self.currentactionsequence == q and self.pp_castinfo.skillid ~= 0 ) then
						GUI:PushStyleColor(GUI.Col_ButtonHovered,0.18,1.0,0.0,0.8)
						GUI:PushStyleColor(GUI.Col_ButtonActive,0.18,1.0,0.0,0.9)
						GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
						GUI:PushStyleColor(GUI.Col_Button,0.18,1.0,0.0,0.7)
						colorset = true	
						labelx = labelx + 35
						labely = labely + size/4
						if ( q > 1 ) then
							label = v.name.." ("..GetString("Active ")..tostring(q).." / "..tostring(#skills)..")"
						else
							label = v.name.." ("..GetString("Active")..")"
						end
						currenltycast = true
						break
					end
				end
						
				if ( not currenltycast ) then
					local count = 0
					for q,s in pairs(skills) do
						if ( s.cooldownmax and s.cooldownmax > 0 ) then 
							if ( s.cooldown and s.cooldown > 0 ) then
								cd = cd + (100 - math.round(s.cooldown*100 / s.cooldownmax, 0))
							else
								cd = cd + 100
							end
							count = count + 1
						end
					end
					if ( count > 0 ) then 	cd = math.round(cd / count,0) end
					
					if ( count > 0 and cd ~= 100 ) then					
						local r,g,b = GUI:ColorConvertHSVtoRGB( cd*0.0045, 0.706, 0.63)					
						GUI:PushStyleColor(GUI.Col_ButtonHovered,r, g, b, 0.8)
						GUI:PushStyleColor(GUI.Col_ButtonActive,r, g, b, 0.9)
						GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
						GUI:PushStyleColor(GUI.Col_Button,r, g, b, 0.7)
						colorset = true
						recx = labelx
						recy = labely 
						recw = labelx+GUI:GetContentRegionAvail()-10 
						rech = labely+size
						labelx = labelx + 35
						labely = labely + size/4
						if ( cd < 0 ) then cd = 0 end
						label = v.name.." ("..tostring(cd).."%)"					
					
					else
						labelx = labelx + 35
						labely = labely + size/4
						if (#skills > 1) then
							label = v.name .." (".. tostring(#skills)..")"
						else
							label = v.name
						end
					end				
				end
				
			elseif ( v.sequence[1].id > 0 ) then
				labelx = labelx + 35
				labely = labely + size/4
				label = "[Missing Skill Data ID: "..tostring(v.sequence[1].id)	
			else
				labelx = labelx + 35
				labely = labely + size/4
				label = "[Empty Action]"				
			end
			
			local cancast = true
			for q,s in pairs(skills) do
				if ( not skillsets[q] or ( s.cooldown and s.cooldown > 0) or not v:CanCastSkill(self, skillsets[q], q)) then
					cancast = false
					break
				end
			end
			if ( cancast ) then
				GUI:ImageButton("##actionlistentry"..tostring(k), texture,size,size)
			else
				GUI:ImageButton("##actionlistentry"..tostring(k), texture,size,size,0,0,1,1,-1, 0,0,0,0,  1,1, 1, 0.4) -- last 4 numbers are rgba
			end
			GUI:SameLine()
			local width = cd~=0 and (GUI:GetContentRegionAvail()-10)/100*cd or  (GUI:GetContentRegionAvail()-10)
			-- Apply drag n drop color
			if ( self.dragid ) then
				if ( self.dragid == k ) then
					GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.5)
				elseif ( self.dropidhover and self.dropidhover == k ) then
					GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.6)
				end
			end

			if ( GUI:Button("##actionlistentrybar"..tostring(k),width,size) ) then
				if ( self.selectedactionid and self.actionlist[self.selectedactionid] ) then self.actionlist[self.selectedactionid]:Deselect() end
				self.selectedskillset = nil
				self.selectedactionid = k
				self.actioneditoropen = true
				self.actionlist[self.selectedactionid].deletecount = nil
			end	
			if ( colorset ) then GUI:PopStyleColor(4) end
			if ( self.dragid and (self.dragid == k or self.dropidhover and self.dropidhover == k )) then GUI:PopStyleColor() end
			
			if ( GUI:IsItemHoveredRect() ) then
				hoveringaction = true				
			end
			-- Drag n Drop to switch places
			if ( GUI:IsItemClicked() ) then
				self.dragid = k
			elseif ( self.dragid and self.dragid ~= k and GUI:IsItemHoveredRect() ) then
				self.dropidhover = k
				if ( GUI:IsMouseReleased(0) ) then
					self.dropid = k
				end
			end
			
	
			-- Draw label
			if ( recx ) then
				GUI:AddRect( recx, recy, recw, rech, GUI:ColorConvertFloat4ToU32(1.0,1.0,1.0,0.2))
			end
						
			GUI:AddText( labelx, labely, GUI:ColorConvertFloat4ToU32(1.0,1.0,1.0,0.80), label)	
		end
		GUI:PopStyleVar(2)
		
		self.pp_castinfo = nil
		self.player = nil
		self.target = nil
		self.sets = nil
		
		-- When moving the mouse outside the window while dragging actions around
		if ( (self.dragid or self.dropidhover) and (hoveringaction == nil and not GUI:IsWindowHovered())) then
			self.dragid = nil
			self.dropidhover = nil
		end
		
		-- Apply Drag n Drop
		if ( self.dragid and self.dropid ) then
			local tmp = self.actionlist[self.dragid]
			self.actionlist[self.dragid] = self.actionlist[self.dropid]
			self.actionlist[self.dropid] = tmp
			-- don't flip skill when it is being edited
			if ( self.selectedactionid and self.actionlist[self.selectedactionid] ) then self.selectedactionid = self.dropid end
			self.dragid = nil
			self.dropid = nil
			self.dropidhover = nil
		end
		
		-- Render 'empty' skill slot on the bottom to add new entries
		local nextid = table.size(self.actionlist) + 1
		if ( GUI:Button("+##"..tostring(nextid), imgsize,imgsize) ) then 
			-- Create a new cast list entry
			local action = sm_action:new()
			action.editskill = 1
			table.insert(self.actionlist,action)
			if ( self.selectedactionid and self.actionlist[self.selectedactionid] ) then self.actionlist[self.selectedactionid]:Deselect() end
			self.selectedskillset = nil
			self.selectedactionid = nextid
			self.actioneditoropen = true
		end
		GUI:EndChild()
		
-- Show Action Editor of the current "selected" action
		if ( self.selectedactionid and self.actionlist[self.selectedactionid] ) then
			local x,y = GUI:GetWindowPos()
			local w,h = GUI:GetWindowSize()
			GUI:SetNextWindowPos( x+w+5, y, GUI.SetCond_Always)
			GUI:SetNextWindowSize(w,h,GUI.SetCond_Appearing)
			local visible
			self.actioneditoropen,visible = GUI:Begin(GetString("Action Editor").."##mlsma", self.actioneditoropen, GUI.WindowFlags_NoSavedSettings+GUI.WindowFlags_AlwaysAutoResize+GUI.WindowFlags_NoCollapse)

			local result = self.actionlist[self.selectedactionid]:Render(self)
			if ( result == -1 ) then
				-- Delete the currently opened action
				table.remove(self.actionlist,self.selectedactionid)
				self.selectedskillset = nil
				self.selectedactionid = nil
				self.actioneditoropen = nil
				self.modified = true
				
			elseif ( result == true ) then 
				self.modified = true 			
			end
			
			GUI:End()
			if ( visible == false ) then
				if ( self.selectedactionid and self.actionlist[self.selectedactionid] ) then self.actionlist[self.selectedactionid]:Deselect()  end
				self.selectedskillset = nil
				self.selectedactionid = nil
				self.actioneditoropen = nil
			end
		end
		GUI:TreePop()
	end
end

-- Show the SkillSet Editor and Skill Selector
function sm_skill_profile:RenderSkillSetEditor(currentaction)
	local modified = false
	GUI:BulletText(GetString("Available Skill Sets:"))
	
	-- Make sure we have at least the "unsortedskillset" Group
	if ( not self.skillsets["All"] ) then		
		self:UpdateCurrentSkillsetData()
		self.selectedskillset = self.skillsets["All"]
		modified = true
	end
	
	-- When opening the editor, select the current skillset and skill
	if ( currentaction.id ~= 0 ) then
		for k,set in pairs(self.skillsets) do
			if (self.selectedskillset ~= nil ) then break end
			for n,m in pairs(set.skills) do
				if (n == currentaction.id) then
					self.selectedskillset = set
					break
				end
			end			
		end		
		-- Select our current active skill
		if (not self.selectedskill and self.selectedskillset and self.selectedskillset.skills[currentaction.id]) then
			self.selectedskill = currentaction.id
		end
	end
	-- 1st time opening this, pick the default list
	if ( not self.selectedskillset ) then self.selectedskillset = self.skillsets["All"] end
	
	GUI:Spacing()
	-- Draw all skillset group buttons, draw the "all skills" first
	if ( self.selectedskillset.id == "All" ) then
		GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
		GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
		GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
		GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
		GUI:Button(self.skillsets["All"].name.."##"..tostring(k),120,25)
		GUI:PopStyleColor(4)
	else
		if ( GUI:Button(self.skillsets["All"].name.."##"..tostring(k),120,25) ) then	
			self.selectedskillset = self.skillsets["All"]
		end
	end
	if ( table.size(self.skillsets) > 1 ) then GUI:SameLine() end
	
	local count = 2
	for k,v in pairs(self.skillsets) do
		if ( k ~= "All" ) then
			if ( k == self.selectedskillset.id ) then
				GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
				GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
				GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
				GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
				GUI:Button(v.name.."##"..tostring(k),120,25)
				GUI:PopStyleColor(4)
			else
				if ( GUI:Button(v.name.."##"..tostring(k),120,25) ) then	
					self.selectedskillset = v
				end
			end		
			if ( math.fmod(count,5) ~= 0 ) then GUI:SameLine() end
			count = count + 1
		end
	end
	
	GUI:Separator()

		
	-- Drawing the actual set details	
	if ( self.selectedskillset ) then
		local profession = SkillManager:GetPlayerProfession() or 0
		GUI:BulletText(GetString("Set Details:"))
		GUI:PushItemWidth(180)
		GUI:Columns(2,"##smbasicedit",false)
		GUI:AlignFirstTextHeightToWidgets()
		GUI:Text(GetString("Set Name:")) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Give this Skillset a name.")) end
		GUI:SameLine(120)
		local	changed
		self.selectedskillset.name, changed = GUI:InputText("##smp3",self.selectedskillset.name)
		if ( changed ) then modified = true end
		
		GUI:AlignFirstTextHeightToWidgets()
		GUI:Text(GetString("Set ID:")) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Internal Skillset ID.")) end
		GUI:SameLine(120)
		self.selectedskillset.id = GUI:InputText("##smp4",self.selectedskillset.id,GUI.InputTextFlags_ReadOnly)		
		
		GUI:NextColumn()
		
	-- Main Skilllist - Refresh /Add / Delete Set buttons
		if ( self.selectedskillset.id == "All" ) then
			if ( GUI:ImageButton("##smadd",sm_skill_profile.texturepath.."\\addon.png",35,35)) then 				
				self:UpdateCurrentSkillsetData()
				modified = true
			end
			if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Add your current Skills.")) end
			GUI:SameLine(310)			
			if ( GUI:ImageButton("##smclear",sm_skill_profile.texturepath.."\\w_delete.png",15,15)) then
				for k,v in pairs(	self.skillsets["All"].skills ) do
					if ( not self:IsSkillInUse(k) ) then -- checks if the current actionlist is using this skill
						self.skillsets["All"].skills[k] = nil
					end
				end
				modified = true
			end
			if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Remove all unused skills of this Set.")) end
		end
		GUI:Columns(1)
		
		-- Set Activate & Deactivate 
		if ( self.selectedskillset and self.selectedskillset.id ~= "All" and table.size(self.selectedskillset.skills) > 0 ) then						
			local combolist = {}
			-- Bundles and Transformations need a defined activate & deactivate skill for the set
			if ( string.starts(self.selectedskillset.id,"2_") or string.starts(self.selectedskillset.id,"3_")) then
				for k,v in pairs(self.selectedskillset.skills) do
					combolist[k] = v.name
				end
				GUI:AlignFirstTextHeightToWidgets()
				GUI:Text(GetString("Activate Set:")) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Select the Skill that activates this Skillset.")) end
				GUI:SameLine(120)
				if ( self.selectedskillset.activateskillid > 2 and self.selectedskillset.skills[self.selectedskillset.activateskillid] ) then
					GUI:ImageButton("##smactivate",sm_skill_profile.texturecache.."\\default.png",20,20)				
				else
					GUI:ImageButton("##smactivate",sm_skill_profile.texturepath.."\\gear.png",20,20)
				end
				GUI:SameLine(155) self.selectedskillset.activateskillid = GUI:Combo("##smactivate",self.selectedskillset.activateskillid or 1, combolist)
				
				-- If this skillset is activated, we also need a deactivate skill id:
				if ( self.selectedskillset.activateskillid > 2 ) then
					GUI:AlignFirstTextHeightToWidgets()
					GUI:Text(GetString("Deactivate Set:"))  if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Select the Skill that deactivates this Skillset.")) end
					GUI:SameLine(120) 
					if ( self.selectedskillset.deactivateskillid and self.selectedskillset.deactivateskillid > 2 and self.selectedskillset.skills[self.selectedskillset.deactivateskillid] ) then
						GUI:ImageButton("##smdeactivate",sm_skill_profile.texturecache.."\\default.png",20,20)					
					else
						GUI:ImageButton("##smdeactivate",sm_skill_profile.texturepath.."\\gear.png",20,20)
					end
					GUI:SameLine(155) self.selectedskillset.deactivateskillid = GUI:Combo("##smdeactivate",self.selectedskillset.deactivateskillid or 1, combolist)
				end
				
				-- Normal weapons which can be swapped
			elseif ( string.starts(self.selectedskillset.id,"4_") or string.starts(self.selectedskillset.id,"0_")) then
				-- Ele's attunements
				if ( SkillManager:GetPlayerProfession() == GW2.CHARCLASS.Elementalist ) then
					if ( string.ends(self.selectedskillset.id,"_1") ) then self.selectedskillset.activateskillid = 13 end -- Fire
					if ( string.ends(self.selectedskillset.id,"_2") ) then self.selectedskillset.activateskillid = 14 end -- Water
					if ( string.ends(self.selectedskillset.id,"_3") ) then self.selectedskillset.activateskillid = 15 end -- Air
					if ( string.ends(self.selectedskillset.id,"_4") ) then self.selectedskillset.activateskillid = 16 end -- Earth
				else
					self.selectedskillset.activateskillid = 2
				end
			end			
		end
		GUI:Separator()
		
-- List the Skills of the SkillSet
		GUI:BulletText(GetString("Skill List:"))
		if ( self.selectedskillset ) then
			if (  self.selectedskillset.id == "All" ) then
				GUI:TextColored( 1.0, 0.75, 0, 1, GetString("Mouse-Right-Click to manage skills"))
			else
				GUI:TextColored( 1.0, 0.75, 0, 1, GetString("1: Move Skills from the Main-Set to this set."))
				GUI:TextColored( 1.0, 0.75, 0, 1, GetString("2: A Skillset must hold ONLY the skills from ONE Weapon / Kit / Stance / Transformation! "))
			end
		end
		if ( self.selectedskillset and table.size(self.selectedskillset.skills) > 0 ) then
			GUI:PushStyleVar(GUI.StyleVar_FramePadding, 2, 2)
			GUI:PushStyleVar(GUI.StyleVar_ItemSpacing, 6, 4)
			
			-- Make 15 columns, insert skills accordingly
			GUI:Columns(16,"##small",false)
			for i=1,16 do			
				GUI:SetColumnOffset(i,i*45)	
				-- Add all skills which are in that "slot"
				local slot = i > 10 and i + 2 or i					
				GUI:Text(sm_skill_profile.slotnames[slot])
				for id,skill in pairs(self.selectedskillset.skills) do						
					if (skill.slot and skill.slot == slot ) then 
						local highlight
						if ( self.selectedskill and self.selectedskill == skill.id ) then 
							highlight = true
							GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.8)
							GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.9)
							GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,1.0)
						end
						
						if ( GUI:ImageButton(skill.name.."##"..tostring(i), sm_skill_profile.texturecache.."\\default.png", 30,30) ) then self.selectedskill = skill.id end if (GUI:IsItemHovered()) then GUI:SetTooltip( skill.name ) end						
						if ( highlight ) then GUI:PopStyleColor(3) end
						-- Right click - Context Menu Spawn
						
						if ( GUI:BeginPopupContextItem("##ctx"..tostring(id)) ) then								
							-- custom sets can only remove / move skills to the Main skill list
							if ( self.selectedskillset.id ~= "All" ) then
								if ( GUI:Selectable(GetString("Move to Main Set"),false) ) then 
									self.skillsets["All"].skills[id] = skill
									self.selectedskillset.skills[id] = nil  
									modified = true 
								end	
								-- Options to move skill to all other sets
							else
								for k,v in pairs(self.skillsets) do
									if (k ~= "All" ) then
										if ( GUI:Selectable(GetString("Move to "..v.name.."##"..tostring(k)),false )) then											
											self.skillsets[k].skills[id] = skill
											self.skillsets["All"].skills[id] = nil
											modified = true 
										end
									end
								end
							
								-- If not used, offer Remove option
								local used = false
								if ( not self:IsSkillInUse(id) ) then
									if ( GUI:Selectable(GetString("Remove"),false) ) then
										self.skillsets["All"].skills[id] = skill
										self.selectedskillset.skills[id] = nil  
										modified = true 
									end
								end
							end
							GUI:EndPopup()
						end
					end
				end
				GUI:NextColumn()
			end
			GUI:Columns(1)			
			GUI:PopStyleVar(2)
		
			-- Selected Skill Details
			if ( self.selectedskill and self.selectedskillset.skills[self.selectedskill] and (self.selectedskillset.id == "All" or self.selectedskillset.activateskillid <= 18 or (self.selectedskillset.activateskillid > 18 and self.selectedskillset.deactivateskillid and self.selectedskillset.deactivateskillid > 2 ))) then
				GUI:Separator()
				local skill = self.selectedskillset.skills[self.selectedskill]
				
				GUI:Columns(2,"##smskilldetails",false)
				GUI:SetColumnOffset(1,60)
				GUI:Dummy(50,10)
				GUI:ImageButton(tostring(skill.name),sm_skill_profile.texturecache.."\\default.png", 40,40) if (GUI:IsItemHovered()) then GUI:SetTooltip( tostring(skill.name) ) end
				GUI:NextColumn()
				
				GUI:BulletText(GetString("Name:")) GUI:SameLine(150) GUI:Text(skill.name)
				GUI:BulletText(GetString("Skill ID:")) GUI:SameLine(150) GUI:Text(skill.id)				
				GUI:BulletText(GetString("Slot:")) GUI:SameLine(150) GUI:Text(skill.slot ~= nil and tostring(skill.slot) or tostring(0))
				GUI:BulletText(GetString("Slot Name:")) GUI:SameLine(150) GUI:Text(skill.slot_name ~= nil and tostring(skill.slot_name) or tostring(""))
				GUI:BulletText(GetString("Type:")) GUI:SameLine(150) GUI:Text(skill.type ~= nil and tostring(skill.type) or tostring(0))
				GUI:BulletText(GetString("Weapon:")) GUI:SameLine(150) GUI:Text(skill.weapon_type ~= nil and tostring(skill.weapon_type) or tostring(0))
				if ( skill.maxrange and skill.maxrange > 0) then GUI:BulletText(GetString("Max.Range:")) GUI:SameLine(150) GUI:Text(tostring(skill.maxrange)) end
				if ( skill.minrange and skill.minrange > 0) then GUI:BulletText(GetString("Min.Range:")) GUI:SameLine(150) GUI:Text(tostring(skill.minrange)) end
				if ( skill.radius and skill.radius > 0 ) then GUI:BulletText(GetString("Radius:")) GUI:SameLine(150) GUI:Text(tostring(skill.radius)) end
				if ( skill.power and skill.power > 0 ) then GUI:BulletText(GetString("Req.Power:")) GUI:SameLine(150) GUI:Text(tostring(skill.power)) end
				if ( skill.flip_level and skill.flip_level > 0 ) then GUI:BulletText(GetString("Chain Level:")) GUI:SameLine(150) GUI:Text(tostring(skill.flip_level)) end
				GUI:Columns(1)
				
				GUI:Separator()
				GUI:Spacing()
				local width = GUI:GetContentRegionAvailWidth()
				if ( currentaction.id ~= 0 ) then
					GUI:SameLine((width/3)-40)
					if ( GUI:Button(GetString("Cancel"), 80,35) ) then
						return -1
					end
					GUI:SameLine((width/3*2)-40)
				else
					GUI:SameLine((width/2)-40)
				end				
				if ( GUI:Button(GetString("Accept"), 80,35) ) then
					currentaction.id = self.selectedskill
					self.selectedskillset = nil					
					return -2
				end
			else
				GUI:Separator()
				GUI:Spacing()
				GUI:Dummy(50,10)
				local width = GUI:GetContentRegionAvailWidth()
				GUI:SameLine((width/3)-40)
				if ( GUI:Button(GetString("Cancel"), 80,35) ) then
					return -1
				end				
			end
		end
	end
	return modified
end

-- Grabs a "snapshot" of the current skills the player has and extends each entry with additional data from the "gw2_skill_data.lua" table.
-- Creates "missing" skill sets and adds skills to the current profile...now this is some major ugly bullshit function ...thanks anet for your chaos profession mechanic!
function sm_skill_profile:UpdateCurrentSkillsetData()
	local skilldb = self.skilldata
	local result = {}			-- Holds all skills of the current set, key is skillID
	for i = 1, ml_global_information.MAX_SKILLBAR_SLOTS-1 do	-- 1 to 19
		local skill = Player:GetSpellInfo(GW2.SKILLBARSLOT["Slot_" .. i])
		if (skill) then
			local sID = skill.skillid
			result[sID] = skill
			result[sID]["slot"] = i
			result[sID]["flip_level"] = 0
			
			-- Add the additional skill data from the anet api file
			local data = skilldb[sID]
			if ( data ) then
				for k,v in pairs (data) do 
					if ( k == "slot" ) then -- slot is also a value we use in the c++ skill table, dont wanna overwrite it
						result[sID]["slot_name"] = v
					else
						result[sID][k] = v
					end
				end
				
				-- Check and add 1st Chain/Flipskill
				if ( data.flip_skill ~= 0 ) then	--flip_skill is the skillID 
					local flip1 = skilldb[data.flip_skill]
					if ( flip1 ) then
						result[flip1.id] = {}
						for k,v in pairs (flip1) do 
							result[flip1.id][k] = v
						end						
						result[flip1.id]["slot_name"] = flip1.slot
						result[flip1.id]["slot"] = i
						result[flip1.id]["flip_level"] = 1
									
						-- 2nd Chain/Flipskill
						if ( flip1.flip_skill ~= 0 ) then
							local flip2 = skilldb[flip1.flip_skill]
							if ( flip2 ) then
								result[flip2.id] = {}
								for k,v in pairs (flip2) do 
									result[flip2.id][k] = v
								end
								result[flip2.id]["slot_name"] = flip2.slot
								result[flip2.id]["slot"] = i
								result[flip2.id]["flip_level"] = 2								
							end				
						end
					end
				end
			end
		end
	end
	--[[-- Add one more custom skill for "weapon swap"
	local ws = Player:GetCurrentWeaponSet()
	if ( ws == 4 or ws == 5 ) then
		result[2] = {
			id = 2,
			skillid = 2,
			slot = 18,
			flip_level = 0,
			slot_name = "None",
			type = "0",
			weapon_type = "0",
			name = GetString("Swap Weapons"),
		}
	end--]]
	
	-- Check, Create and update "Unsorted Skills"
	if ( not self.skillsets["All"] ) then
		-- Add a new "unsortedskillset" skillset
		local set = sm_skillset:new()
		set.id = "All"
		set.name = GetString("All Skills")		
		set.skills = {}		
		self.skillsets["All"] = set
	end
	
	local w = Player:GetCurrentWeaponSet()
	local t = Player:GetTransformID()
	
	--Engineer, create 1 Set for the active Bundle, skills 1-5 
	if ( w == 2 ) then -- engi bundles have all id 2, use additionally skill1 id to seperat them. skills 1-5
		if ( self.currentskills and self.currentskills[3] ) then
			self:CreateSetFromSkillData("2_"..tostring(self.currentskills[3].skillid), result, 1, 5, GetString("Bundle Set"))
		end
	
	-- All Transformations, ele, necro, warrior, engi, changes only skills 1-5
	elseif ( w == 3 ) then
		-- Necro has 2 kinds of transformation...-.-
		if ( SkillManager:GetPlayerProfession() == 8 ) then
			self:CreateSetFromSkillData("3_"..tostring(t), result, 1, 5, GetString("Transform Set"))
		else
			self:CreateSetFromSkillData("3", result, 1, 5, GetString("Transform Set"))
		end
				
	else
		local weapon1
		local weapon2
		-- Get 2 different "ids" in case it is a 1Hand weapon
		if ( w == 0 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AquaticWeapon)
			if ( item ) then weapon1 = "0_"..tostring(item.weapontype) end	-- 0 for all water weapons
		elseif( w == 1 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AlternateAquaticWeapon)
			if ( item ) then weapon1 = "0_2_"..tostring(item.weapontype) end
		elseif ( w == 4 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.MainHandWeapon)
			if ( item ) then weapon1 = "4_"..tostring(item.weapontype) end	-- 4 for all "land" weapons, since they can be in either hand or slot
			local item2 = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.OffHandWeapon)
			if ( item2 ) then weapon2 = "4_2_"..tostring(item2.weapontype) end
		elseif ( w == 5 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AlternateMainHandWeapon)
			if ( item ) then weapon1 ="4_"..tostring(item.weapontype) end
			local item2 = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AlternateOffHandWeapon)
			if ( item2 ) then weapon2 = "4_2_"..tostring(item2.weapontype) end
		end
		
		-- Elementalist, combine attunement + weapontype		
		if ( t >0 and t < 5 ) then			
			if ( weapon2 ) then
				self:CreateSetFromSkillData(weapon1.."_"..tostring(t), result, 1, 3, GetString("New Set"))
				self:CreateSetFromSkillData(weapon2.."_"..tostring(t), result, 4, 5, GetString("New Set2"))
								
			else
				self:CreateSetFromSkillData(weapon1.."_"..tostring(t), result, 1, 5, GetString("New Set"))
			end
						
		
		-- Revenant, up to 3 set ids .. weapons + stances
		elseif( t > 11 and t < 18 ) then
			if ( weapon2 ) then
				self:CreateSetFromSkillData(weapon1, result, 1, 3, GetString("New Set"))
				self:CreateSetFromSkillData(weapon2, result, 4, 5, GetString("New Set2"))
				self:CreateSetFromSkillData(tostring(t), result, 6, 10, GetString("New Set3"))
			else
				self:CreateSetFromSkillData(weapon1, result, 1, 5, GetString("New Set"))
				self:CreateSetFromSkillData(tostring(t), result, 6, 10, GetString("New Set2"))
			end
		
		else
			if ( weapon2 ) then
				self:CreateSetFromSkillData(weapon1, result, 1, 3, GetString("New Set"))
				self:CreateSetFromSkillData(weapon2, result, 4, 5, GetString("New Set2"))								
			else
				self:CreateSetFromSkillData(weapon1, result, 1, 5, GetString("New Set"))
			end
		end		
	end
	
	-- Add remaining skills to our unsorted skills if we don't have them yet
	for k,v in pairs ( result ) do
		if ( not self:GetSkill(k) ) then
			self.skillsets["All"].skills[k] = v
		end
	end
end

-- Helper to reduce the redudant code spam
function sm_skill_profile:CreateSetFromSkillData(id, skills, slotmin, slotmax, name)
	if ( not self.skillsets[id] ) then		
		local set = sm_skillset:new()
		set.id = id				
		set.skills = {}
		
		local namefixed
		if(id == "12") then namefixed = GetString("Dragon ")
		elseif(id == "13") then namefixed = GetString("Assassin ")
		elseif(id == "14") then namefixed = GetString("Dwarf ")
		elseif(id == "15") then namefixed = GetString("Deamon ")
		elseif(id == "17") then namefixed = GetString("Centaur ")		
		end
		set.name = namefixed or name
		
		for k,v in pairs ( skills ) do
			if ( v.slot >= slotmin and v.slot <= slotmax ) then set.skills[k] = v end
					
			if ( set.name == "" and v.slot == 1 ) then 
				if ( v.weapon_type and v.weapon_type ~= "None" ) then
					if ( slotmin == 4 ) then
						set.name = v.weapon_type.." 2" 
					else
						set.name = v.weapon_type 
					end
				end
			end
		end
		self.skillsets[id] = set				
	end
end

-- Gets the additional skilldata from the gw2_skiull.data file and returns that
function sm_skill_profile:GetSkillDataByID( skillid )
	local skilldb = self.skilldata
	if (skilldb) then		
		local data = skilldb[skillid]
		if ( data ) then
			local result = {}
			for k,v in pairs (data) do 
				if ( k == "slot" ) then -- slot is also a value we use in the c++ skill table, dont wanna overwrite it
					result["slot_name"] = v
				else
					result[k] = v
				end
			end
			return result
		end		
	else
		ml_error("[SkillManager] - Invalid skill data file!")
	end
end

-- Finds the skill (data) in all skillsets and returns that
function sm_skill_profile:GetSkill(id)
	for k,v in pairs(self.skillsets) do
		if (v.skills[id]) then
			return v.skills[id], v
		end
	end
end

-- Checks if the skill ID is used by the current profile/castlist
function sm_skill_profile:IsSkillInUse(skillid)
	for k,v in pairs(self.actionlist) do
		for a,s in pairs(v.sequence) do
			if ( s.id == skillid) then
				return true
			end
		end
	end
	return false
end

-- Updates the Data of the current SkillSets
function sm_skill_profile:Update(gametick)
	if ( not self.lasttick or gametick - self.lasttick > 50 ) then
		self.lasttick = gametick
		self.currentskills = {}
		self.activeskillrange = 154
		
		-- Use the current gamedata to update the skillset data
		for i = 1, ml_global_information.MAX_SKILLBAR_SLOTS-1 do	-- 1 to 19
			local skill = Player:GetSpellInfo(GW2.SKILLBARSLOT["Slot_" .. i])
			if (skill) then
				self.currentskills[i] = skill
				local setskill = self:GetSkill(skill.skillid)
				if (setskill ) then
					setskill.cooldown = skill.cooldown
					setskill.cooldownmax = skill.cooldownmax
					if ( setskill.isgroundtargeted == nil ) then setskill.isgroundtargeted = skill.isgroundtargeted end
					if ( setskill.slot >= 7 and setskill.slot <=9 ) then
						setskill.slot = i
					end
											
					self.activeskillrange = (setskill.maxrange > 0 and setskill.maxrange > self.activeskillrange and setskill.maxrange or self.activeskillrange)
					self.activeskillrange = (setskill.radius > 0 and setskill.radius > self.activeskillrange and setskill.radius or self.activeskillrange)
				end
			end
		end
		
		local cdlist = Player:GetCoolDownList()
		if ( cdlist ) then
			for id,e in pairs(cdlist) do
				local setskill = self:GetSkill(id)
				if (setskill ) then
					setskill.cooldown = e.cooldown
					self.cooldownlist[id] = { tick = gametick, cd = e.cooldown }
				end
			end
		end
		
		-- in case our skill arrived at 0 cooldown, it would disappear from the GetCoolDownList, this code makes sure our data is set back to 0 
		for id, e in pairs (self.cooldownlist) do
			if ( gametick - e.tick >= e.cd ) then
				local setskill = self:GetSkill(id)
				if (setskill ) then
					setskill.cooldown = 0
				end
				table.remove(self.cooldownlist,id)
			end		
		end
		
		ml_global_information.AttackRange = self.activeskillrange
	end
end


--********** SKILLSET 'CLASS' *************
-- the "container class" that groups together selected skills
function sm_skillset:initialize( data )
	if ( not data ) then data = {} end
	self.id = data.id or ""													-- internal id, 0 for unsortedskillset  and 4_0 for ex. for "Main Weapon" , it is a combinated string from Weaponset and GetTransformID
	self.name = data.name or ""										-- skillset name
	self.activateskillid = data.activateskillid or 1				-- default id for "swap weapons"
	self.deactivateskillid = data.deactivateskillid or nil
	self.skills = data.skills or {}										-- all skills of this set,  tablekey is skillid
end

function sm_skillset:GetSkill(id)
	for k,v in pairs(self.skills) do
		if (k==id) then
			return v			
		end
	end
end


--********** ACTION 'CLASS' *************

-- Action "class" used by the Actionlist. Holding all variables and data for skills, conditions etc.
-- Default Class ctor
function sm_action:initialize(data)
	if ( not data ) then		
		self.sequence = { [1] = {id = 0, settings = {}, conditions = {} }}
	else
		self:Load(data)
	end
end
-- Saves all action data into a table and returns that for saving
function sm_action:Save()
	local data = {}
	data.name = self.name or GetString("[Empty Action]")
	data.sequence = {}
	local idx = 1
	for a,s in pairs ( self.sequence ) do
		s.conditioncodefunc = nil
		data.sequence[idx] = { id = s.id, settings = s.settings, conditioncode = s.conditioncode, conditions = {}, }		
		if ( table.valid(s.conditions) ) then
			for i,or_group in pairs(s.conditions) do			
				for k,v in pairs(or_group) do
					if ( type(v) == "table") then
						if ( not data.sequence[idx].conditions[i] ) then data.sequence[idx].conditions[i] = {} end
						data.sequence[idx].conditions[i][k] = v:Save()
					end				
				end
			end
		end
		idx = idx + 1
	end	
	return data
end
-- Loads the action from a former saved data table
function sm_action:Load(data)	
	self.name = data.name
	self.sequence = {}
	for a,s in pairs ( data.sequence ) do
		self.sequence[a] = {}
		self.sequence[a].id = s.id
		self.sequence[a].settings = s.settings or {}
		self.sequence[a].conditioncode = s.conditioncode
		self.sequence[a].conditions = {}		
		if ( table.valid(s.conditions) ) then		
			for i,or_group in pairs(s.conditions) do			
				self.sequence[a].conditions[i] = {}	-- create the "OR" group			
				for k,v in pairs(or_group) do
					if ( string.valid(v.class) ) then
						local condtemplate = SkillManager:GetCondition(v.class)				
						if ( condtemplate ) then
							local condition = condtemplate:new()	
							condition:Load(v)					
							self.sequence[a].conditions[i][k] = condition
						else
							ml_error("[SkillManager] - Unable To Load Condition, condition class not registered in SkillManager: "..tostring(v.class))
						end
							
					else
						ml_error("[SkillManager] - Unable To Load Condition, Invalid Condition Class on skill ID "..tostring(self.sequence[a].id))
					end
				end			
			end
		end
	end
end

function sm_action:Deselect()
	self.editskill = nil
	self.selectedskill = nil
	for k,v in pairs(self.sequence) do
		v.deletecount = nil
	end
end

-- Renders the Action Info, Details, Editor etc.
function sm_action:Render(profile)
	local modified
	if ( not self.selectedskill ) then 
		self.selectedskill = select(1,next(self.sequence))		
		if ( self.selectedskill and self.sequence[self.selectedskill].id == 0 ) then 
			self.editskill = self.selectedskill
		end
	end
		
	if ( self.editskill ) then 
		local result = profile:RenderSkillSetEditor(self.sequence[self.editskill])
		if ( result == -1 ) then -- cancel
			self.editskill = nil 
		elseif ( result == -2 ) then -- accept
			if ( not self.name or not string.valid(self.name) or self.name == GetString("[Empty Action]") ) then
				local skill = profile:GetSkill(self.sequence[self.editskill].id)		
				if ( skill ) then self.name = skill.name end
			end
			self.editskill = nil 
			modified = true
			
		elseif ( result == true ) then
			modified = true
		end
			
	else
		
		GUI:AlignFirstTextHeightToWidgets()
		GUI:PushItemWidth(180)
		GUI:Text(GetString("Name:"))
		local changed
		GUI:SameLine(100)
		self.name, changed = GUI:InputText( "##actionname", self.name or GetString("[Empty Action]"))
		GUI:PopItemWidth()
		if ( changed ) then modified = true end	
			
		GUI:SameLine(599)	
		local highlighted
		if ( self.deletecount ) then
			GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
			GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
			GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
			GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
			highlighted = true
		end
		if ( GUI:ImageButton("##smdelete",profile.texturepath.."\\w_delete.png",13,13)) then -- delete whole action, not just a single skill of the sequence
			self.deletecount = self.deletecount ~= nil and 2 or 1
			if ( self.deletecount == 2 ) then
				GUI:PopStyleColor(4)
				return -1 
			end		
		end
		if ( highlighted ) then GUI:PopStyleColor(4) end
		GUI:Separator()
		
	-- Skill Sequence Buttons
		GUI:Text(GetString("Skill Sequence:"))
		if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Add multiple skills to create a Combo. Skills are cast in order from 'Left' to 'Right'!")) end
		local neededheight = math.max(40, math.ceil(#self.sequence / 11)*40 )
		GUI:BeginChild("##actionsequence", 600,neededheight)
		local count = 1
		for k,v in pairs ( self.sequence ) do
			local highlight
			if ( self.selectedskill == k ) then
				GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.8)
				GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.9)
				GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,1.0)
				highlight = true
			end		
			local skill = profile:GetSkill(v.id)	
			if ( skill ) then
				if ( GUI:ImageButton("##smseq"..tostring(k), profile.texturecache.."\\default.png",30,30) ) then				
					self.selectedskill = k				
				end
			else
				if ( GUI:ImageButton("##smseq"..tostring(k), profile.texturecache.."\\blank.png",30,30) ) then
					self.selectedskill = k
				end
			end
			if ( highlight ) then GUI:PopStyleColor(3) end
			local name = skill and skill.name or GetString("Skill")
			if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Select").." "..name) end
			
			count = count + 1
			if (count % 13 ~= 0) then GUI:SameLine() end			
		end
		
		-- Add new Skill to Sequence button		
		if ( GUI:Button("+##sequence", 35, 35) ) then 
			-- Create a new cast list entry
			table.insert(self.sequence, {id = 0, conditions = {} })
			self.editskill = #self.sequence
			self.selectedskill = #self.sequence
		end		
		if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Add a Skill to the Sequence, to create a Combo")) end
		GUI:EndChild()
	
		GUI:Separator()
		if ( self.selectedskill and self.sequence[self.selectedskill] ) then
			GUI:Text(GetString("Skill Details:"))
		-- Skill Delete button
			if ( #self.sequence > 1 ) then
				GUI:SameLine(599)	
				local highlighted
				if ( self.sequence[self.selectedskill].deletecount ) then
					GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
					GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
					GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
					GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
					highlighted = true
				end
				if ( GUI:ImageButton("##smdeleteskill",profile.texturepath.."\\w_delete.png",13,13)) then -- delete whole action, not just a single skill of the sequence
					self.sequence[self.selectedskill].deletecount = self.sequence[self.selectedskill].deletecount ~= nil and 2 or 1
					if ( self.sequence[self.selectedskill].deletecount == 2 ) then
						GUI:PopStyleColor(4)
						table.remove(self.sequence,self.selectedskill)
						return true
					end		
				end
				if ( highlighted ) then GUI:PopStyleColor(4) end
			end
			
			GUI:Columns(3)
			GUI:SetColumnOffset(1,60)
			GUI:SetColumnOffset(2,375)
			GUI:Dummy(30,10)
			local skill, set = profile:GetSkill(self.sequence[self.selectedskill].id)
			if ( skill ) then
				if ( GUI:ImageButton("##sm"..tostring(i), sm_skill_profile.texturecache.."\\default.png",40,40) ) then				
					self.editskill = self.selectedskill
				end
			else
				if ( GUI:ImageButton("##sm"..tostring(i), sm_skill_profile.texturecache.."\\blank.png",40,40) ) then
					self.editskill = self.selectedskill
				end
			end
			if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Change the Skill.")) end
			
			if ( skill ) then
				GUI:NextColumn()
			
				GUI:BulletText(GetString("Name:")) GUI:SameLine(125) GUI:Text(skill.name)
				GUI:BulletText(GetString("Skill ID:")) GUI:SameLine(125) GUI:Text(skill.id)				
				GUI:BulletText(GetString("Slot:")) GUI:SameLine(125) GUI:Text(skill.slot ~= nil and tostring(skill.slot) or tostring(0))
				GUI:BulletText(GetString("Type:")) GUI:SameLine(125) GUI:Text(skill.type ~= nil and tostring(skill.type) or tostring(0))
				GUI:BulletText(GetString("Weapon:")) GUI:SameLine(125) GUI:Text(skill.weapon_type ~= nil and tostring(skill.weapon_type) or tostring(0))
				if ( skill.flip_level and skill.flip_level > 0 ) then GUI:BulletText(GetString("Chain Level:")) GUI:SameLine(125) GUI:Text(tostring(skill.flip_level)) end
				GUI:NextColumn()
				if ( skill.maxrange and skill.maxrange > 0) then GUI:BulletText(GetString("Max.Range:")) GUI:SameLine(125) GUI:Text(tostring(skill.maxrange)) end
				if ( skill.minrange and skill.minrange > 0) then GUI:BulletText(GetString("Min.Range:")) GUI:SameLine(125) GUI:Text(tostring(skill.minrange)) end
				if ( skill.radius and skill.radius > 0 ) then GUI:BulletText(GetString("Radius:")) GUI:SameLine(125) GUI:Text(tostring(skill.radius)) end
				if ( skill.power and skill.power > 0 ) then GUI:BulletText(GetString("Req.Power:")) GUI:SameLine(125) GUI:Text(tostring(skill.power)) end				
				if ( skill.cooldownmax ) then
					if ( skill.cooldown ) then GUI:BulletText(GetString("Cooldown:")) GUI:SameLine(125) GUI:Text(tostring(skill.cooldown).. " / "..tostring(skill.cooldownmax))
					else
						GUI:BulletText(GetString("Cooldown:")) GUI:SameLine(125) GUI:Text(" 0 / "..tostring(skill.cooldownmax))
					end
				end
				GUI:BulletText(GetString("Skill Set:")) GUI:SameLine(125) GUI:Text(tostring(set.name))
				local currentsets = profile:GetCurrentSkillSets()
				for q,currentset in pairs ( currentsets ) do
					if ( currentset ) then
						GUI:BulletText(GetString("Current Sets: ")) GUI:SameLine(125) GUI:Text(tostring(currentset.name))
					end
				end
			
				GUI:Columns(1)
				GUI:Separator()
		-- Skill Settings
				GUI:Text(GetString("Skill Settings:"))	if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Special Settings for this Skill" )) end
				local changed
				self.sequence[self.selectedskill].settings.setsattackrange, changed = GUI:Checkbox( GetString("Sets Attackrange"), self.sequence[self.selectedskill].settings.setsattackrange or false) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("If Enabled, the 'MaxRange' of the Skill defines the Attackrange of the bot." )) end if (changed) then modified = true end
				GUI:SameLine(200)
				self.sequence[self.selectedskill].settings.nolos, changed = GUI:Checkbox( GetString("No Line of Sight"), self.sequence[self.selectedskill].settings.nolos or false) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("If Enabled, the line of sight to the target will not be checked when casting." )) end if (changed) then modified = true end
				GUI:SameLine(400)
				self.sequence[self.selectedskill].settings.stopmovement, changed = GUI:Checkbox( GetString("Stop Movement"), self.sequence[self.selectedskill].settings.stopmovement or false) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("If Enabled, the bot movement will be stopped while casting the skill." )) end if (changed) then modified = true end
				self.sequence[self.selectedskill].settings.castonplayer, changed = GUI:Checkbox( GetString("Cast on Player"), self.sequence[self.selectedskill].settings.castonplayer or false) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("If Enabled, the Skill will be cast on the Player and not on the Target." )) end if (changed) then modified = true end
				GUI:SameLine(200)
				self.sequence[self.selectedskill].settings.castslow, changed = GUI:Checkbox( GetString("Cast Slow"), self.sequence[self.selectedskill].settings.castslow or false) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("If Enabled, the Skill will be cast slower and not skipped." )) end if (changed) then modified = true end
				GUI:SameLine(400)
				self.sequence[self.selectedskill].settings.isprojectile, changed = GUI:Checkbox( GetString("Is Projectile"), self.sequence[self.selectedskill].settings.isprojectile or false) if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Enable this only if the Skill cannot be cast on some objects." )) end if (changed) then modified = true end				
								
				
				GUI:Separator()
				
				GUI:Spacing()
		
		-- Condition Builder
				GUI:Text(GetString("Cast if:"))	if (GUI:IsItemHovered()) then GUI:SetTooltip( GetString("Cast this Skill if..." )) end
				GUI:BeginChild("##actioncondigrp", 625,300)
				if ( table.size(self.sequence[self.selectedskill].conditions) > 0 ) then
					for idx,or_group in pairs(self.sequence[self.selectedskill].conditions) do
						for k,v in pairs(or_group) do
							if ( type(v) == "table") then
								if (v:Render(tostring(idx)..tostring(k))) then modified = true end
								GUI:SameLine(590)
								local highlighted
								if ( v.deletecount ) then
									GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
									GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
									GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
									GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
									highlighted = true
								end	
								if ( GUI:ImageButton("##actiondelcondi"..tostring(idx)..""..tostring(k),profile.texturepath.."\\w_delete.png",15,15)) then
									v.deletecount = v.deletecount ~= nil and 2 or 1
									if ( v.deletecount == 2 ) then
										self.sequence[self.selectedskill].conditions[idx][k] = nil
										if ( table.size(self.sequence[self.selectedskill].conditions[idx]) == 0) then
											self.sequence[self.selectedskill].conditions[idx] = nil
										end
										modified = true
									end
								end
								if ( highlighted ) then GUI:PopStyleColor(4) end
							end
						end
						
									
						-- Add New Condition Button
						if ( or_group.addnew ) then
							local conditions = SkillManager:GetConditions()
							if ( table.valid(conditions)) then
								local combolist = {}
								local i = 1
								for k,v in pairs(conditions) do
									combolist[i] = GetString(tostring(v))
									i = i+1
								end
								or_group.addnew = GUI:Combo("##addcondinew",or_group.addnew, combolist)
								if ( combolist[or_group.addnew]) then
									GUI:SameLine()
									if (GUI:Button(GetString("Add").."##addnewcond"..tostring(idx), 50,20)) then
										for k,v in pairs(conditions) do						
											or_group.addnew = or_group.addnew-1
											if ( or_group.addnew == 0 ) then
												local newcond = v:new()
												table.insert(self.sequence[self.selectedskill].conditions[idx], newcond)
												or_group.addnew = nil
												modified = true
												break
											end
										end					
									end
								end
							else
								GUI:Text("ERROR: NO CONDITIONS REGISTERED IN THE SKILLMANAGER")
							end
						elseif ( GUI:Button(GetString("+ AND").."##addcondi"..tostring(idx), 60,20)) then 
							self.sequence[self.selectedskill].conditions[idx].addnew = 1
						end
						
						if ( idx < #self.sequence[self.selectedskill].conditions ) then
							GUI:Text(GetString("OR Cast if:"))
						end
					end
							
					-- Add a new OR Group:
					GUI:Spacing()
					if (GUI:Button(GetString("+ OR").."##addcondOR"..tostring(idx), 60,20)) then
						local newgroup = { addnew = 1, }
						table.insert(self.sequence[self.selectedskill].conditions,newgroup)
					end
					
				else
					if (GUI:Button(GetString("+ Add New Condition").."##addcondOR2", 150,20)) then
						local newgroup = { addnew = 1, }
						table.insert(self.sequence[self.selectedskill].conditions,newgroup)
					end
				end
					
				GUI:EndChild()
				
				GUI:Spacing()
				GUI:Spacing()
				GUI:Separator()
		
		-- Custom Condition editor
				local _,maxy = GUI:GetContentRegionAvail()
				GUI:SetNextTreeNodeOpened(false,GUI.SetCond_Once)
				if ( GUI:TreeNode(GetString("CUSTOM CONDITION CODE EDITOR")) ) then			
					if ( GUI:IsItemHovered() ) then GUI:SetTooltip(GetString("Write you own Lua code, when to cast this skill. Must return 'true' or 'false'!")) end
					local maxx,_ = GUI:GetContentRegionAvail()
					local changed = false
					self.sequence[self.selectedskill].conditioncode, changed = GUI:InputTextEditor( "##smactioncodeeditor", self.sequence[self.selectedskill].conditioncode or GetString("-- Return 'true' when the skill can be cast, else return 'false'. Use the 'context' table to share data between all skills.\nreturn true"), maxx, math.max(maxy/2,300) , GUI.InputTextFlags_AllowTabInput)
					if ( changed ) then self.sequence[self.selectedskill].conditioncodechanged = true modified = true end
					if ( self.sequence[self.selectedskill].conditioncodechanged ) then
						GUI:PushStyleColor(GUI.Col_Button,1.0,0.75,0.0,0.7)
						GUI:PushStyleColor(GUI.Col_ButtonHovered,1.0,0.75,0.0,0.8)
						GUI:PushStyleColor(GUI.Col_ButtonActive,1.0,0.75,0.0,0.9)
						GUI:PushStyleColor(GUI.Col_Text,1.0,1.0,1.0,1.0)
						if ( GUI:Button(GetString("Save Changes"),maxx,20) ) then
							self.sequence[self.selectedskill].conditioncodechanged = nil
							profile:Save()
						end				
						GUI:PopStyleColor(4)
					end
					GUI:PushItemWidth(600)
					GUI:Dummy(600,1)
					GUI:PopItemWidth()
					GUI:TreePop()
				end
				GUI:Separator()
			end
		end
	end
	
	return modified
end


-- Checks if a skill of the sequence can be cast by evaluating all conditions
function sm_action:CanCastSkill(profile, targetskillset, sequenceid)
	if ( self.sequence[sequenceid] ~= nil ) then
		-- Check if we need to swap sets and if that is possible			
		local swapresult = profile:GetSkillsetCastID(targetskillset)
		if ( swapresult == false )  then
			return false -- We cannot currently "reach" the skillset which contains this skill
		elseif( swapresult == -1 ) then	-- we have the set equipped, now check if the skill is actually there
			-- Check if the skill id we want to cast is actually on the current skillbar
			local skill = self.sequence[sequenceid]
			local skilldata, skillset = profile:GetSkill(skill.id)
			if ( not skilldata or not profile.currentskills[skilldata.slot] or (profile.currentskills[skilldata.slot].skillid ~= skill.id and skilldata.flip_level == 0)) then -- exclude all skilldata.flip_level > 0, to allow combos				
				return false
			end
		end
		
		local skill = self.sequence[sequenceid]
		if ( not skill ) then 
			return false
		end
		
		-- Basic Settings
		if ( not skill.settings.castonplayer and not profile.target ) then return false end 
		if ( not skill.settings.nolos and not profile.target.los) then return false end
		
		-- Evaluate custom code first		
		if ( skill.conditioncode ) then
			if ( not skill.conditioncodefunc ) then
				local execstring = 'return function(self, context) '..skill.conditioncode..' end'
				local func = loadstring(execstring)
				if ( func ) then
					func()(skill, profile.context)
					skill.conditioncodefunc = func	
				else				
					ml_error("[SkillManager] - Custom Condition Code Editor compilation error in Action ".. tostring(self.name ~= "" and self.name or "").." at skill "..tostring(sequenceid))
					assert(loadstring(execstring)) -- print out the actual error
				end
			end
			
			if ( skill.conditioncodefunc and not skill.conditioncodefunc()(skill, profile.context) ) then 
				return false
			end
		end
		
		-- Go through all Conditions
		if ( #skill.conditions > 0 ) then
			for i,or_group in pairs( skill.conditions ) do
				-- Either of the or_groups needs to be true for the skill to be castable
				local cancast = true
				for k,v in pairs(or_group) do
					if ( type(v) == "table") then
						if ( not v:Evaluate(profile.player, profile.target) ) then
							cancast = false
							break
						end
					end
				end
				if ( cancast ) then	return true end
			end
			return false
		end
		return true -- in case there is only custom condition code or no code at all
	end
	return false
end

-- Returns the skill ID to cast, for the case we have to swap to the Targetskillset
function sm_skill_profile:GetSkillsetCastID(targetskillset)
	for k,v in pairs (self.sets) do
		if ( v.name == targetskillset.name ) then
			return -1	-- We currently have the targetskillset equipped, no need to switch
		end
	end
	
	
	-- Can we switch to that new set by swapping weapons ?
	if ( targetskillset.activateskillid == 2 ) then	-- target set can be activated by swapping weapons
		if (( Player:CanSwapWeaponSet() or Player:GetCurrentWeaponSet() == 2 ) -- we can swap weapons or player is engi and has a bundle equipped where we can just swap out
			and ((string.starts(targetskillset.id,"4_") and self.player.swimming == 0)	-- target set is W1 / W2 and we are on land
				or ( string.starts(targetskillset.id,"0_") and self.player.swimming == 1))) 	then-- or taget set is Aqua1/2 and we are under water						
			return -2
		else
			return false -- we cannot swap to that set right now
		end
	else
	
		-- Ele's attunements
		local prof = SkillManager:GetPlayerProfession()
		if ( prof == GW2.CHARCLASS.Elementalist ) then
			if ( string.ends(targetskillset.id,"_1") ) then	 -- Fire
				if ( self.currentskills[13] and self.currentskills[13].cooldown == 0 ) then 
					return 13 
				else
					return false
				end
			
			elseif ( string.ends(targetskillset.id,"_2") )then  -- Water
				if (self.currentskills[14] and self.currentskills[14].cooldown == 0 ) then 
					return 14 
				else
					return false
				end
				
			elseif ( string.ends(targetskillset.id,"_3") ) then -- Air
				if (self.currentskills[15] and self.currentskills[15].cooldown == 0 ) then 
					return 15 
				else
					return false
				end
				
			elseif ( string.ends(targetskillset.id,"_4") ) then -- Earth
				if (self.currentskills[16] and self.currentskills[16].cooldown == 0 ) then 
					return 16 
				else
					return false
				end
			end
		end
			
		-- Revenant's stances
		if (prof == GW2.CHARCLASS.Revenant ) then
			if(targetskillset.id == "12") then --Dragon switch skill ID 28229				
				if ( self.currentskills[13] and self.currentskills[13].skillid == 28229 and self.currentskills[13].cooldown == 0 ) then return 13
				elseif (self.currentskills[17] and self.currentskills[17].skillid == 28229 and self.currentskills[17].cooldown == 0) then return 17					
				else return false
				end
			elseif(targetskillset.id == "13") then --Assassin switch skill ID 27659				
				if ( self.currentskills[13] and self.currentskills[13].skillid == 27659 and self.currentskills[13].cooldown == 0 ) then return 13
				elseif (self.currentskills[17] and self.currentskills[17].skillid == 27659 and self.currentskills[17].cooldown == 0) then return 17					
				else return false
				end				
			elseif(targetskillset.id == "14") then --Dwarf switch skill ID 26650
				if ( self.currentskills[13] and self.currentskills[13].skillid == 26650 and self.currentskills[13].cooldown == 0 ) then return 13
				elseif (self.currentskills[17] and self.currentskills[17].skillid == 26650 and self.currentskills[17].cooldown == 0) then return 17					
				else return false
				end
			elseif(targetskillset.id == "15") then --Deamon switch skill ID 28376
				if ( self.currentskills[13] and self.currentskills[13].skillid == 28376 and self.currentskills[13].cooldown == 0 ) then return 13
				elseif (self.currentskills[17] and self.currentskills[17].skillid == 28376 and self.currentskills[17].cooldown == 0) then return 17					
				else return false
				end
			elseif(targetskillset.id == "17") then --Centaur switch skill ID 28141
				if ( self.currentskills[13] and self.currentskills[13].skillid == 28141 and self.currentskills[13].cooldown == 0 ) then return 13
				elseif (self.currentskills[17] and self.currentskills[17].skillid == 28141 and self.currentskills[17].cooldown == 0) then return 17					
				else return false
				end		
			end
		end
		
		-- Check if the activateskillid of the targetskillset is on our current skillset and can be cast, so we can swap to that set
		for sid, sk in pairs (self.currentskills) do				
			if ( sk.skillid == targetskillset.activateskillid ) then -- find the slot of the activate skill
				local skilldata = self:GetSkill(targetskillset.activateskillid)						
				if ( skilldata and (not skilldata.cooldown or skilldata.cooldown == 0) ) then
					return skilldata.slot
				end
			end
		end
			
			-- not sure if that is needed, so far only necro shroud would use it, but that can as well be fixed by setting a combo skill before one of the other shroud skills,  to swap out of it
			--[[ check if the targetskillset is weapon1 or weapon2 set, assuming that activateskillid == 2 is ONLY used by these two sets, in that case, deactivating the current set should bring us to w1 or w2
			if ( self.set.deactivateskillid and self.set.deactivateskillid > 2 
				and (((string.starts(targetskillset.id,"4_") or string.starts(targetskillset.id,"5_")) and self.player.swimming == 0)	-- target set is W1 / W2 and we are on land
				or((string.starts(targetskillset.id,"0_") or string.starts(targetskillset.id,"1_")) and self.player.swimming == 1)))	then-- or taget set is Aqua1/2 and we are under water		
				
				-- Check if the deactivateskillid of the targetskillset is on our current skillset and can be cast, so we can swap to that set
				for sid, sk in pairs (self.currentskills) do				
					if ( sk.skillid == self.set.deactivateskillid ) then -- find the slot of the activate skill
						local skilldata = self:GetSkill(self.set.deactivateskillid)						
						if ( skilldata and (not skilldata.cooldown or skilldata.cooldown == 0) ) then
							return skilldata.slot
						end
					end
				end
				return 
				 
			end--]]
	end
	return -3
end

-- Generates a unique ID to identify skillsets..silly anet..such a mess -.-
-- redudant code... jukk....but nothing I can do about :(
function sm_skill_profile:GetCurrentSkillSetIDs(currentskilldata)
	local w = Player:GetCurrentWeaponSet()
	local t = Player:GetTransformID()
	
	--Engineer, create 1 Set for the active Bundle, skills 1-5 
	if ( w == 2 ) then -- engi bundles have all id 2, use additionally skill1 id to seperat them
		if ( self.currentskills and self.currentskills[3] ) then
			return "2_"..tostring(self.currentskills[3].skillid)
		end
	
	-- All Transformations, ele, necro, warrior, engi, changes only skills 1-5
	elseif ( w == 3 ) then
		-- Necro has 2 kinds of transformation...-.-
		if ( SkillManager:GetPlayerProfession() == 8 ) then
			return "3_"..tostring(t)
		else
			return "3"
		end
		
	else
		local weapon1
		local weapon2
		-- Get 2 different "ids" in case it is a 1Hand weapon
		if ( w == 0 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AquaticWeapon)
			if ( item ) then weapon1 = "0_"..tostring(item.weapontype) end	-- 0 for all water weapons
		elseif( w == 1 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AlternateAquaticWeapon)
			if ( item ) then weapon1 = "0_2_"..tostring(item.weapontype) end
		elseif ( w == 4 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.MainHandWeapon)
			if ( item ) then weapon1 = "4_"..tostring(item.weapontype) end	-- 4 for all "land" weapons, since they can be in either hand or slot
			local item2 = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.OffHandWeapon)
			if ( item2 ) then weapon2 = "4_2_"..tostring(item2.weapontype) end
		elseif ( w == 5 ) then
			local item = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AlternateMainHandWeapon)
			if ( item ) then weapon1 ="4_"..tostring(item.weapontype) end
			local item2 = Inventory:GetEquippedItemBySlot(GW2.EQUIPMENTSLOT.AlternateOffHandWeapon)
			if ( item2 ) then weapon2 = "4_2_"..tostring(item2.weapontype) end
		end
		
		-- Elementalist, combine attunement + weapontype 
		if ( t >0 and t < 5 ) then
			if ( weapon2 ) then
				return weapon1.."_"..tostring(t), weapon2.."_"..tostring(t)-- 2 weapons, skills 1-3 , 4-5
			else
				return weapon1.."_"..tostring(t)	-- 1 weapon, skills 1-5
			end
		
		-- Revenant, return up to 3 set ids .. weapons + stances
		elseif( t > 11 and t < 18 ) then
			if ( weapon2 ) then				
				return weapon1, weapon2, tostring(t)-- 2 weapons, skills 1-3 , 4-5 and stance skills 6-10
			else
				return weapon1, tostring(t)-- 1 weapon, skills 1-5 and stance skills 6-10
			end
		
		else
			if ( weapon2 ) then
				return weapon1, weapon2 -- 2 weapons, skills 1-3 , 4-5
			else
				return weapon1 -- 1 weapon, skills 1-5
			end		
		end		
	end
end

-- Which sets we are currently having active
function sm_skill_profile:GetCurrentSkillSets()
	local id,id2,id3 = self:GetCurrentSkillSetIDs() -- we can have up to 3 sets active at the same time @Revenant
	
	local availablesets = {}
	table.insert(availablesets,self.skillsets["All"])
	if ( id and self.skillsets[id] ) then table.insert(availablesets,self.skillsets[id]) end
	if ( id2 and self.skillsets[id2] ) then table.insert(availablesets,self.skillsets[id2]) end
	if ( id3 and self.skillsets[id3] ) then table.insert(availablesets,self.skillsets[id3]) end
	
	return availablesets
end

-- Gets "next" skill that can be cast.
function sm_skill_profile:GetNextSkillForCasting()
	-- We casted an action before, check if this action is a sequence and pick the next skill if possible
	if ( self.currentaction ) then
		self.currentactionsequence = self.currentactionsequence + 1 
		local action = self.actionlist[self.currentaction]
		if ( action.sequence[self.currentactionsequence] ) then
			local skilldata, skillset = self:GetSkill(action.sequence[self.currentactionsequence].id)
			if ( skilldata and (not skilldata.cooldown or skilldata.cooldown == 0) and action:CanCastSkill(self, skillset, self.currentactionsequence)) then				
				return true
			end
		end
	end
	
	-- We need a new action which we can cast
	for k,action in pairs(self.actionlist) do
		-- check if all skills in an action sequence can be cast, before selecting it ... this has some limitations obviously in the cancast conditions...
		local cancast = true
		for i,skill in pairs(action.sequence) do
			local skilldata, skillset = self:GetSkill(skill.id)
			if ( not skilldata or ( skilldata.cooldown and skilldata.cooldown > 0) or not action:CanCastSkill(self, skillset, i)) then				
				cancast = nil
			end			
		end
		if ( cancast ) then
			self.currentaction = k
			self.currentactionsequence = 1
			return true
		end
	end
	self.currentaction = nil
	self.currentactionsequence = nil	
end


-- Casting
function sm_skill_profile:Cast(targetid)
	local target = CharacterList:Get(targetid) or GadgetList:Get(targetid) --or AgentList:Get(targetid)
	
	self.pp_castinfo = Player.castinfo
	self.player = Player
	self.target = target
	self.sets = self:GetCurrentSkillSets()
		
	-- Setting a "current action to cast"
	if ( not self.currentaction ) then self:GetNextSkillForCasting() end
	
	if ( self.currentaction ) then
		local action = self.actionlist[self.currentaction]
		if ( not action ) then 
			-- someone deleted an action from the list
			self.currentaction = nil
			self.currentactionsequence = nil	
			return false
		end
		local skilldata, skillset = self:GetSkill(action.sequence[self.currentactionsequence].id)		
		if ( skilldata ) then
			
			-- Make sure we can still cast the spell that we picked earlier, if somethign changed and we cannot cast it, get a new skill instead
			if (( not skilldata.cooldown or skilldata.cooldown == 0) and not self.pp_castinfo.skillid == skilldata.id and not action:CanCastSkill(self, skillset, self.currentactionsequence)) then					
				self.currentaction = nil
				self.currentactionsequence = nil	
				if (self:GetNextSkillForCasting() ) then	-- get a new spell
					action = self.actionlist[self.currentaction]
					skilldata, skillset = self:GetSkill(action.sequence[self.currentactionsequence].id)								
				else
					return false
				end
			end
			
			-- If skill is already on CD, or if it is a spammable skill and our lastskillid is showing we cast it, get the next skill in the sequence OR a new action
			if ( (skilldata.cooldown and skilldata.cooldown ~= 0) or (skilldata.cooldownmax and skilldata.cooldownmax == 0 and self.pp_castinfo.lastskillid == skilldata.id)) then
				if (self:GetNextSkillForCasting() ) then-- get a new / next skill
					action = self.actionlist[self.currentaction]
					skilldata, skillset = self:GetSkill(action.sequence[self.currentactionsequence].id)								
				else
					return false
				end
			end
			
			
			-- We are not casting the skill yet,...trying to do so ...
			if (skilldata and (not skilldata.cooldown or skilldata.cooldown == 0) and (self.pp_castinfo.skillid ~= skilldata.id or (skilldata.slot == 1 and skilldata.cooldownmax and skilldata.cooldownmax == 0))) then
				-- Ensure the correct Weapon Set
				local switchslot = self:GetSkillsetCastID(skillset) 
				if ( switchslot == -2 ) then
					-- swap weapons
					Player:SwapWeaponSet()
					d("Swapping weaponset..")
					return true
				elseif ( switchslot >= 0 ) then
					-- cast spell to swap sets
					Player:CastSpell(GW2.SKILLBARSLOT["Slot_" .. switchslot])
					d("Swapping weaponset to "..tostring(GW2.SKILLBARSLOT["Slot_" .. switchslot]))
					return true
				elseif ( switchslot == -3 ) then
					d(tostring(skilldata.name)" .. is not on the skillset or it cannot be switched to. Check Activate / Deactivate Skills of that Set")
					return false
				end
				
				
				-- Cast
				if ( action.sequence[self.currentactionsequence].settings.castonplayer) then
					self.target = Player
				end
				
				if ( not target ) then return end
				local castresult
				if (skilldata.groundtargeted) then
					local pos = self.target.pos
					-- extend cast position by radius if the target is slightly outside
					-- 5% extra range
					-- increasing height slightly -> extra range
					-- calc in radius -> extra range
					if (self.target.ischaracter) then
						castresult = Player:CastSpell(GW2.SKILLBARSLOT["Slot_" .. skilldata.slot] , pos.x, pos.y, pos.z)
					elseif (self.target.isgadget) then
						if (skilldata.isprojectile) then
							castresult = Player:CastSpell(GW2.SKILLBARSLOT["Slot_" .. skilldata.slot] , pos.x, pos.y, pos.z)
						else
							castresult = Player:CastSpell(GW2.SKILLBARSLOT["Slot_" .. skilldata.slot] , pos.x, pos.y, (pos.z - self.target.height))
						end
					end
				else
					castresult = Player:CastSpell(GW2.SKILLBARSLOT["Slot_" .. skilldata.slot] , self.target.id)
				end
			
				if ( castresult ) then
					d("Casting: "..skilldata.name)
					return true
				else
					d("Casting Failed: "..skilldata.name)
				end
							
			end
		else
			ml_error("[SkillManager] - Invalid Skilldata for casting, ID : "..tostring(action.sequence[self.currentactionsequence].id))
		end
	end
	self.pp_castinfo = nil
	self.player = nil
	self.target = nil
	self.sets = nil
	
	return false
end


-- To load the additional skill data
function sm_skill_profile.Init()
	sm_skill_profile.skilldata = FileLoad(GetStartupPath()  .. "\\LuaMods\\SkillManager\\gw2_skill_data.lua")
	if ( not table.valid(sm_skill_profile.skilldata) ) then
		ml_error("[SkillManager] - Failed to load Skill Data!")
	end
end
RegisterEventHandler("Module.Initalize",sm_skill_profile.Init)


-- Register this template in the SM Mgr
SkillManager:RegisterProfileTemplate( sm_skill_profile )