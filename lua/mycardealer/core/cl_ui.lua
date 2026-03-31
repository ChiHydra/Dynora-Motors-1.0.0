--[[
    myCardealer Tier 1 Core: UI Infrastructure
    Compact single-file UI system with registered DFrames
]]

-- Create global UI table immediately
myCardealer.UI = myCardealer.UI or {
    Frames = {},      -- Registered frame types
    ActiveFrames = {}, -- Currently open windows
    Colors = {
        Primary    = Color(157, 78, 221),
        PrimaryDark= Color(120, 60, 180),
        Secondary  = Color(30, 30, 30),
        Background = Color(20, 20, 20),
        Surface    = Color(35, 35, 35),
        SurfaceLit = Color(45, 45, 45),
        Text       = Color(255, 255, 255),
        TextDim    = Color(180, 180, 180),
        Error      = Color(220, 50, 50),
        Success    = Color(50, 220, 50),
        Warning    = Color(220, 180, 50)
    }
}

-- Register fonts
surface.CreateFont("myCardealer.Header", {font = "Roboto", size = 20, weight = 700})
surface.CreateFont("myCardealer.Title",  {font = "Roboto", size = 16, weight = 600})
surface.CreateFont("myCardealer.Body",   {font = "Roboto", size = 14, weight = 400})
surface.CreateFont("myCardealer.Small",  {font = "Roboto", size = 12, weight = 400})
surface.CreateFont("myCardealer.Mono",   {font = "Consolas", size = 13, weight = 400})

-- Color helper
function myCardealer.UI:Color(name)
    return self.Colors[name] or color_white
end

--[[-------------------------------------------------------------------------
    REGISTERED FRAME: Base Window
---------------------------------------------------------------------------]]

local PANEL_FRAME = {}

function PANEL_FRAME:Init()
    self:SetTitle("")
    self:ShowCloseButton(false)
    self:DockPadding(0, 28, 0, 0)
    
    -- Title bar
    self.TitleBar = vgui.Create("DPanel", self)
    self.TitleBar:Dock(TOP)
    self.TitleBar:SetTall(28)
    self.TitleBar.Paint = function(p, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Primary"))
        surface.DrawRect(0, 0, w, h)
        
        if self._Title then
            draw.SimpleText(self._Title, "myCardealer.Title", 10, 4, color_white)
        end
    end
    
    -- Close button
    local close = vgui.Create("DButton", self.TitleBar)
    close:Dock(RIGHT)
    close:SetWide(28)
    close:SetText("×")
    close:SetFont("myCardealer.Header")
    close:SetTextColor(color_white)
    close.Paint = function() end
    close.DoClick = function() self:Close() end
    
    -- Content container
    self.Content = vgui.Create("DPanel", self)
    self.Content:Dock(FILL)
    self.Content:DockPadding(8, 8, 8, 8)
    self.Content.Paint = function(p, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Background"))
        surface.DrawRect(0, 0, w, h)
    end
end

function PANEL_FRAME:SetTitleText(t)
    self._Title = t
end

function PANEL_FRAME:GetContent()
    return self.Content
end

function PANEL_FRAME:Paint(w, h)
    -- Shadow
    surface.SetDrawColor(0, 0, 0, 100)
    surface.DrawRect(4, 4, w, h)
    -- Main
    surface.SetDrawColor(myCardealer.UI:Color("Surface"))
    surface.DrawRect(0, 0, w, h)
    -- Border
    surface.SetDrawColor(myCardealer.UI:Color("Primary"))
    surface.DrawOutlinedRect(0, 0, w, h, 1)
end

-- Register the frame type
vgui.Register("myCardealer.Frame", PANEL_FRAME, "DFrame")
myCardealer.UI.Frames.Base = "myCardealer.Frame"

--[[-------------------------------------------------------------------------
    REGISTERED FRAME: Panel with sidebar layout
---------------------------------------------------------------------------]]

local PANEL_SIDEBAR = {}

function PANEL_SIDEBAR:Init()
    self:DockPadding(0, 28, 0, 0)
    
    -- Title bar (simplified)
    self.TitleBar = vgui.Create("DPanel", self)
    self.TitleBar:Dock(TOP)
    self.TitleBar:SetTall(28)
    self.TitleBar.Paint = function(p, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Primary"))
        surface.DrawRect(0, 0, w, h)
    end
    
    -- Sidebar
    self.Sidebar = vgui.Create("DPanel", self)
    self.Sidebar:Dock(LEFT)
    self.Sidebar:SetWide(180)
    self.Sidebar:DockMargin(0, 0, 0, 0)
    self.Sidebar.Paint = function(p, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Secondary"))
        surface.DrawRect(0, 0, w, h)
    end
    
    self.SidebarList = vgui.Create("DScrollPanel", self.Sidebar)
    self.SidebarList:Dock(FILL)
    self.SidebarList:DockPadding(4, 4, 4, 4)
    self.SidebarList.VBar:SetWide(6)
    
    -- Main content area
    self.MainContent = vgui.Create("DPanel", self)
    self.MainContent:Dock(FILL)
    self.MainContent.Paint = function(p, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Background"))
        surface.DrawRect(0, 0, w, h)
    end
    
    -- Bottom bar
    self.BottomBar = vgui.Create("DPanel", self)
    self.BottomBar:Dock(BOTTOM)
    self.BottomBar:SetTall(44)
    self.BottomBar:DockMargin(0, 0, 0, 0)
    self.BottomBar.Paint = function(p, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Surface"))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Primary"))
        surface.DrawRect(0, 0, w, 1)
    end
end

function PANEL_SIDEBAR:AddSidebarItem(name, callback)
    local btn = vgui.Create("DButton", self.SidebarList)
    btn:Dock(TOP)
    btn:SetTall(36)
    btn:DockMargin(0, 0, 4, 2)
    btn:SetText("")
    
    btn.Paint = function(p, w, h)
        local col = p:IsHovered() and myCardealer.UI:Color("SurfaceLit") or myCardealer.UI:Color("Surface")
        surface.SetDrawColor(col)
        surface.DrawRect(0, 0, w, h)
        
        if p.Selected then
            surface.SetDrawColor(myCardealer.UI:Color("Primary"))
            surface.DrawRect(0, 0, 3, h)
        end
        
        draw.SimpleText(name, "myCardealer.Body", 10, 9, color_white)
    end
    
    btn.DoClick = function()
        -- Deselect all
        for _, child in pairs(self.SidebarList:GetCanvas():GetChildren()) do
            if child.Selected then child.Selected = false end
        end
        btn.Selected = true
        callback()
    end
    
    return btn
end

function PANEL_SIDEBAR:GetContent()
    return self.MainContent
end

function PANEL_SIDEBAR:GetBottomBar()
    return self.BottomBar
end

function PANEL_SIDEBAR:Paint(w, h)
    surface.SetDrawColor(0, 0, 0, 100)
    surface.DrawRect(4, 4, w, h)
    surface.SetDrawColor(myCardealer.UI:Color("Surface"))
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(myCardealer.UI:Color("Primary"))
    surface.DrawOutlinedRect(0, 0, w, h, 1)
end

vgui.Register("myCardealer.Frame.Sidebar", PANEL_SIDEBAR, "EditablePanel")
myCardealer.UI.Frames.Sidebar = "myCardealer.Frame.Sidebar"

--[[-------------------------------------------------------------------------
    UI HELPERS: Buttons, Lists, etc.
---------------------------------------------------------------------------]]

-- Create styled button (returns DButton)
function myCardealer.UI:Button(parent, label, color)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetTall(32)
    
    local baseColor = color or self:Color("Primary")
    local hoverColor = Color(
        math.min(baseColor.r + 20, 255),
        math.min(baseColor.g + 20, 255),
        math.min(baseColor.b + 20, 255)
    )
    
    btn.Paint = function(p, w, h)
        surface.SetDrawColor(p:IsHovered() and hoverColor or baseColor)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(255, 255, 255, 20)
        surface.DrawRect(0, 0, w, h/2)
        draw.SimpleText(label, "myCardealer.Body", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    return btn
end

-- Create styled list
function myCardealer.UI:List(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll.VBar:SetWide(6)
    scroll.VBar.Paint = function(p, w, h)
        surface.SetDrawColor(self:Color("Secondary"))
        surface.DrawRect(0, 0, w, h)
    end
    scroll.VBar.btnGrip.Paint = function(p, w, h)
        surface.SetDrawColor(self:Color("Primary"))
        surface.DrawRect(0, 0, w, h)
    end
    return scroll
end

-- Create list item
function myCardealer.UI:ListItem(parent, title, subtitle, color)
    local item = vgui.Create("DButton", parent)
    item:Dock(TOP)
    item:DockMargin(0, 0, 6, 2)
    item:SetTall(48)
    item:SetText("")
    
    local baseColor = self:Color("Surface")
    local litColor = self:Color("SurfaceLit")
    local accent = color or self:Color("Primary")
    
    item.Paint = function(p, w, h)
        if p.Selected then
            surface.SetDrawColor(Color(40, 50, 40))
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(accent)
            surface.DrawRect(0, 0, 3, h)
        else
            surface.SetDrawColor(p:IsHovered() and litColor or baseColor)
            surface.DrawRect(0, 0, w, h)
        end
        
        draw.SimpleText(title, "myCardealer.Body", 10, 6, color_white)
        if subtitle then
            draw.SimpleText(subtitle, "myCardealer.Small", 10, 26, self:Color("TextDim"))
        end
    end
    
    return item
end

-- Create label
function myCardealer.UI:Label(parent, text, font)
    local lbl = vgui.Create("DLabel", parent)
    lbl:SetFont(font or "myCardealer.Body")
    lbl:SetText(text)
    lbl:SetTextColor(self:Color("Text"))
    lbl:SizeToContents()
    return lbl
end

--[[-------------------------------------------------------------------------
    WINDOW MANAGEMENT
---------------------------------------------------------------------------]]

-- Open a registered frame type
function myCardealer.UI:Open(frameType, w, h, title)
    frameType = frameType or "Base"
    local className = self.Frames[frameType] or "myCardealer.Frame"
    
    -- Close existing of same type
    if self.ActiveFrames[frameType] and IsValid(self.ActiveFrames[frameType]) then
        self.ActiveFrames[frameType]:Remove()
    end
    
    local frame = vgui.Create(className)
    frame:SetSize(w or 600, h or 400)
    frame:Center()
    if title then frame:SetTitleText(title) end
    frame:MakePopup()
    
    self.ActiveFrames[frameType] = frame
    return frame
end

-- Close all myCardealer windows
function myCardealer.UI:CloseAll()
    for _, frame in pairs(self.ActiveFrames) do
        if IsValid(frame) then frame:Remove() end
    end
    self.ActiveFrames = {}
end

-- Mark as Tier 1 loaded
myCardealer.Core = myCardealer.Core or {}
myCardealer.Core.TierLoaded = myCardealer.Core.TierLoaded or {}
myCardealer.Core.TierLoaded[1] = true

print("[myCardealer] Tier 1 Core UI loaded")