-- Подпишитесь на канал Tg: @promt114
-- Чтобы развить наш канал.

-- MM2 Visuals | Only visuals, no aimbot, no rage
-- Совместим: Madium, Xeno, Real, Velocity, Sirhurt, Volt, Potassium, Delta, Trigon X, Arceus X, Codex

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInput     = game:GetService("UserInputService")
local CoreGui       = game:GetService("CoreGui")
local LocalPlayer   = Players.LocalPlayer

-- Settings
local S = {
    -- Box ESP
    Box           = true,
    BoxStyle      = "Full",   -- "Full" | "Corner" | "Bracket"
    BoxColor      = Color3.fromRGB(255, 255, 255),
    BoxThickness  = 1,
    BoxFilled     = false,
    BoxFillOpacity = 20,      -- 0-100

    -- Name + Distance
    Name          = true,
    NameColor     = Color3.fromRGB(255, 255, 255),
    Distance      = true,
    DistColor     = Color3.fromRGB(200, 200, 200),

    -- Skeleton
    Skeleton      = false,
    SkeletonColor = Color3.fromRGB(255, 255, 255),

    -- Highlight Chams (Occluded)
    Chams         = true,
    ChamsFill     = Color3.fromRGB(78, 127, 252),
    ChamsFillT    = 0.5,       -- 0 = opaque, 1 = invisible
    ChamsOutline  = Color3.fromRGB(255, 255, 255),
    ChamsOutlineT = 0,

    -- Material Chams (ForceField, Glass, Ice, Foil...)
    MatChams      = false,
    MatStyle      = "ForceField", -- "ForceField"|"Flat"|"Glass"|"Ice"|"Ghost"|"Marble"|"Foil"|"Metal"|"Wood"
    MatColor      = Color3.fromRGB(120, 200, 255),
    MatTransp     = 0,         -- extra transparency 0-1

    -- Toggle key
    ToggleKey     = Enum.KeyCode.RightShift,
    Enabled       = true,
}

-- ─── Render helpers (ported from Salad Visuals source) ─────────────────────

local Render = {}

do
    local _cam = workspace.CurrentCamera
    function Render.camera()
        local c = workspace.CurrentCamera
        if c ~= _cam then _cam = c end
        return _cam
    end

    function Render.basis()
        local cam = Render.camera()
        if not cam then return nil end
        local cf       = cam.CFrame
        local viewport = cam.ViewportSize
        local half     = math.tan(math.rad(cam.FieldOfView) * 0.5)
        return {
            pos      = cf.Position,
            look     = cf.LookVector,
            right    = cf.RightVector,
            up       = cf.UpVector,
            midX     = viewport.X * 0.5,
            midY     = viewport.Y * 0.5,
            scale    = (viewport.Y * 0.5) / half,
            viewport = viewport,
        }
    end

    function Render.project(basis, point)
        local dx    = point.X - basis.pos.X
        local dy    = point.Y - basis.pos.Y
        local dz    = point.Z - basis.pos.Z
        local depth = dx * basis.look.X + dy * basis.look.Y + dz * basis.look.Z
        if depth <= 0.05 then return 0, 0, depth end
        local inv = basis.scale / depth
        return basis.midX + (dx * basis.right.X + dy * basis.right.Y + dz * basis.right.Z) * inv,
               basis.midY - (dx * basis.up.X    + dy * basis.up.Y    + dz * basis.up.Z)    * inv,
               depth
    end
end

-- ─── Visibility cache (ported from Salad Visuals source) ───────────────────

local Visibility = {}
do
    local cache = setmetatable({}, { __mode = "k" })

    function Visibility.Part(camera, part, target)
        if not (camera and part and part.Parent and part:IsA("BasePart") and target) then return false end
        local origin   = camera.CFrame.Position
        local position = part.Position
        local dir      = position - origin
        local dist     = dir.Magnitude
        if dist ~= dist or dist == math.huge then return false end
        if dist < 0.001 then return true end
        local now = os.clock()
        local own = LocalPlayer.Character
        local saved = cache[part]
        if saved and saved.Target == target and saved.Own == own and saved.Camera == camera
            and now < saved.Expires
            and (origin - saved.Origin).Magnitude < 0.5
            and (position - saved.Position).Magnitude < 0.5 then
            return saved.Visible
        end
        local params = saved and saved.Params or RaycastParams.new()
        params.FilterType    = Enum.RaycastFilterType.Exclude
        params.IgnoreWater   = true
        local ignored = { target }
        if own and own ~= target then ignored[#ignored + 1] = own end
        local visible = false
        for _ = 1, 8 do
            params.FilterDescendantsInstances = ignored
            local ok, hit = pcall(workspace.Raycast, workspace, origin, dir, params)
            if not ok then break end
            if not hit then visible = true; break end
            local obj = hit.Instance
            if obj and obj:IsA("BasePart") and obj.Transparency >= 0.99 then
                ignored[#ignored + 1] = obj
            else
                break
            end
        end
        cache[part] = {
            Target = target, Own = own, Camera = camera,
            Origin = origin, Position = position,
            Expires = now + 0.08, Visible = visible, Params = params,
        }
        return visible
    end

    function Visibility.Character(camera, char, root)
        if not char then return false end
        local head  = char:FindFirstChild("Head")
        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        return Visibility.Part(camera, head, char)
            or Visibility.Part(camera, root, char)
            or Visibility.Part(camera, torso, char)
    end
end

-- ─── Box projection (ported from Salad Visuals source) ─────────────────────

local BODY_NAMES = {
    Head=true, Torso=true, UpperTorso=true, LowerTorso=true,
    ["Left Leg"]=true, ["Right Leg"]=true,
    LeftUpperLeg=true, LeftLowerLeg=true, LeftFoot=true,
    RightUpperLeg=true, RightLowerLeg=true, RightFoot=true,
}

local extentsCache = setmetatable({}, { __mode = "k" })

local function getExtents(char, root)
    local held = extentsCache[char]
    if held and os.clock() - held.at < 0.5 then return held end
    local inv = root.CFrame:Inverse()
    local lo  = Vector3.new(math.huge, math.huge, math.huge)
    local hi  = Vector3.new(-math.huge, -math.huge, -math.huge)
    local any = false
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and BODY_NAMES[part.Name] then
            local cf   = inv * part.CFrame
            local half = part.Size * 0.5
            local rv, uv, lv = cf.RightVector, cf.UpVector, cf.LookVector
            local spread = Vector3.new(
                math.abs(rv.X)*half.X + math.abs(uv.X)*half.Y + math.abs(lv.X)*half.Z,
                math.abs(rv.Y)*half.X + math.abs(uv.Y)*half.Y + math.abs(lv.Y)*half.Z,
                math.abs(rv.Z)*half.X + math.abs(uv.Z)*half.Y + math.abs(lv.Z)*half.Z
            )
            lo  = lo:Min(cf.Position - spread)
            hi  = hi:Max(cf.Position + spread)
            any = true
        end
    end
    if not any then return nil end
    local torso  = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or root
    local height = math.clamp((hi.Y - lo.Y), 0.5, 24)
    local halfV  = Vector3.new(
        math.clamp(torso.Size.X * 0.6, height * 0.16, height * 0.24),
        height * 0.5,
        math.clamp(torso.Size.Z * 0.55, 0.15, height * 0.16)
    )
    held = { at = os.clock(), center = Vector3.new(0, (lo.Y + hi.Y) * 0.5, 0), half = halfV }
    extentsCache[char] = held
    return held
end

local CORNERS = {
    Vector3.new(-1,-1,-1), Vector3.new(1,-1,-1), Vector3.new(1,-1,1), Vector3.new(-1,-1,1),
    Vector3.new(-1, 1,-1), Vector3.new(1, 1,-1), Vector3.new(1, 1,1), Vector3.new(-1, 1,1),
}
local BOX_EDGES = {{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
local screenCorners = {}

local function clipNear(a, b)
    local near = 0.1
    if a.Z > -near and b.Z > -near then return nil end
    if a.Z > -near then a = a:Lerp(b, (-near - a.Z) / (b.Z - a.Z)) end
    if b.Z > -near then b = b:Lerp(a, (-near - b.Z) / (a.Z - b.Z)) end
    return a, b
end

local function projectPoint(point, camera, viewport)
    local focal = viewport.Y / (2 * math.tan(math.rad(camera.FieldOfView) * 0.5))
    return Vector2.new(
        viewport.X * 0.5 + point.X * focal / -point.Z,
        viewport.Y * 0.5 - point.Y * focal / -point.Z
    )
end

local function clipViewport(a, b, viewport)
    local dx, dy  = b.X - a.X, b.Y - a.Y
    local low, hi = 0, 1
    for _, pair in ipairs({{-dx,a.X},{dx,viewport.X-a.X},{-dy,a.Y},{dy,viewport.Y-a.Y}}) do
        local p, q = pair[1], pair[2]
        if p == 0 then
            if q < 0 then return nil end
        else
            local t = q / p
            if p < 0 then low = math.max(low, t) else hi = math.min(hi, t) end
            if low > hi then return nil end
        end
    end
    return a:Lerp(b, low), a:Lerp(b, hi)
end

local function projectBox(char, camera, viewport)
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not camera or viewport.X <= 0 or viewport.Y <= 0 then return nil end
    local box = getExtents(char, root)
    if not box then return nil end
    local relative = camera.CFrame:Inverse() * root.CFrame
    for i, corner in ipairs(CORNERS) do
        screenCorners[i] = relative * (box.center + corner * box.half)
    end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local segments, projected = {}, 0
    for _, edge in ipairs(BOX_EDGES) do
        local a, b = clipNear(screenCorners[edge[1]], screenCorners[edge[2]])
        if a then
            a, b = projectPoint(a, camera, viewport), projectPoint(b, camera, viewport)
            projected += 1
            minX, minY = math.min(minX, a.X, b.X), math.min(minY, a.Y, b.Y)
            maxX, maxY = math.max(maxX, a.X, b.X), math.max(maxY, a.Y, b.Y)
            a, b = clipViewport(a, b, viewport)
            if a then segments[#segments + 1] = {a, b} end
        end
    end
    if projected == 0 or maxX < 0 or minX > viewport.X or maxY < 0 or minY > viewport.Y then return nil end
    minX, minY = math.max(minX, 0), math.max(minY, 0)
    maxX, maxY = math.min(maxX, viewport.X), math.min(maxY, viewport.Y)
    if maxX - minX < 1 or maxY - minY < 1 then return nil end
    return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY), segments
end

-- ─── Material Chams (ported from Salad Visuals source) ──────────────────────

local MATERIAL_STYLES = {
    ForceField = { material = Enum.Material.ForceField,    reflectance = 0,    transparency = 0,    tint = true },
    Flat       = { material = Enum.Material.SmoothPlastic, reflectance = 0,    transparency = 0,    tint = true },
    Glass      = { material = Enum.Material.Glass,         reflectance = 0.12, transparency = 0.28, tint = true },
    Ice        = { material = Enum.Material.Ice,           reflectance = 0.1,  transparency = 0.16, tint = true },
    Ghost      = { material = Enum.Material.SmoothPlastic, reflectance = 0.02, transparency = 0.58, tint = true },
    Marble     = { material = Enum.Material.Marble,        reflectance = 0.04, transparency = 0,    tint = true },
    Foil       = { material = Enum.Material.Foil,          reflectance = 0.12, transparency = 0,    tint = true },
    Metal      = { material = Enum.Material.Metal,         reflectance = 0.3,  transparency = 0,    tint = true },
    Wood       = { material = Enum.Material.Wood,          reflectance = 0,    transparency = 0,    tint = true },
}

local paintCache = {}

local function restoreModel(model)
    if model == nil then
        for m in pairs(paintCache) do restoreModel(m) end
        return
    end
    local data = paintCache[model]
    if not data then return end
    for part, orig in pairs(data.parts) do
        if part.Parent then
            part.Material    = orig.Material
            part.Color       = orig.Color
            part.Transparency = orig.Transparency
            part.Reflectance = orig.Reflectance
            pcall(function() part.MaterialVariant = orig.MaterialVariant end)
            if orig.TextureID then pcall(function() part.TextureID = orig.TextureID end) end
        end
    end
    for mesh, tex in pairs(data.meshes or {}) do
        if mesh.Parent then pcall(function() mesh.TextureId = tex end) end
    end
    for inst, parent in pairs(data.hidden) do
        if parent and parent.Parent then pcall(function() inst.Parent = parent end)
        else pcall(function() inst:Destroy() end) end
    end
    paintCache[model] = nil
end

local function paintModel(model, styleName, color, extraT)
    local style = (type(styleName) == "table" and styleName) or MATERIAL_STYLES[styleName]
    if not style then restoreModel(model); return end
    local alpha = math.clamp(tonumber(extraT) or 0, 0, 1)
    local finalT = 1 - (1 - style.transparency) * (1 - alpha)
    if not paintCache[model] then paintCache[model] = { parts = {}, hidden = {}, meshes = {} } end
    local data = paintCache[model]
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            if not data.parts[inst] then
                data.parts[inst] = {
                    Material        = inst.Material,
                    MaterialVariant = inst.MaterialVariant,
                    Color           = inst.Color,
                    Transparency    = inst.Transparency,
                    Reflectance     = inst.Reflectance,
                    TextureID       = inst:IsA("MeshPart") and inst.TextureID or nil,
                }
            end
            if data.parts[inst].Transparency < 1 then
                inst.Material    = style.material or data.parts[inst].Material
                inst.Reflectance = style.reflectance
                inst.Transparency = finalT
                inst.Color       = style.tint and color or data.parts[inst].Color
                pcall(function() inst.MaterialVariant = "" end)
                if inst:IsA("MeshPart") then pcall(function() inst.TextureID = "" end) end
                local mesh = inst:FindFirstChildOfClass("SpecialMesh")
                if mesh then
                    if data.meshes[mesh] == nil then data.meshes[mesh] = mesh.TextureId end
                    pcall(function() mesh.TextureId = "" end)
                end
            end
        elseif inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic")
            or inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") then
            if data.hidden[inst] == nil and inst.Parent then
                data.hidden[inst] = inst.Parent
                pcall(function() inst.Parent = nil end)
            end
        end
    end
end

-- ─── Skeleton bones (ported from Salad Visuals source) ──────────────────────

local R15_BONES = {
    {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"}, {"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"}, {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"},
}
local R6_BONES = {
    {"Head","Torso"},
    {"Torso","Left Arm"}, {"Torso","Right Arm"},
    {"Torso","Left Leg"}, {"Torso","Right Leg"},
}

-- ─── Drawing pool (ported from Salad Visuals source) ────────────────────────

local function makePool(class, setup)
    local items, used = {}, 0
    local pool = {}
    function pool.take()
        used += 1
        if not items[used] then
            items[used] = Drawing.new(class)
            if setup then setup(items[used]) end
        end
        return items[used]
    end
    function pool.reset() used = 0 end
    function pool.done()
        for i = used + 1, #items do
            if items[i] and items[i].Visible then items[i].Visible = false end
        end
    end
    function pool.wipe()
        for i = 1, #items do pcall(function() items[i]:Remove() end) end
        table.clear(items); used = 0
    end
    return pool
end

-- ─── Per-player bundle ──────────────────────────────────────────────────────

local bundles    = {}
local highlights = {}
local hlState    = {}
local matPainted = {}

local DARK = Color3.fromRGB(0, 0, 0)

local function getBundle(player)
    if bundles[player] then return bundles[player] end
    local b = {
        nameLabel = Drawing.new("Text"),
        distLabel = Drawing.new("Text"),
        fill      = (function()
            local sq = Drawing.new("Square")
            sq.Filled = true; sq.Visible = false; return sq
        end)(),
        bars     = {},
        outlines = {},
        edges    = {},
        bones    = {},
    }
    b.nameLabel.Size   = 13; b.nameLabel.Center = true
    b.nameLabel.Outline = true; b.nameLabel.Font = 2
    b.nameLabel.Visible = false
    b.distLabel.Size   = 11; b.distLabel.Center = true
    b.distLabel.Outline = true; b.distLabel.Font = 2
    b.distLabel.Visible = false
    bundles[player] = b
    return b
end

local function hidePool(pool, from)
    for i = from, #pool do pool[i].Visible = false end
end

local function rect(pool, idx, at, size, color)
    local p = pool[idx]
    if not p then
        p = Drawing.new("Square"); p.Filled = true; p.Thickness = 1
        pool[idx] = p
    end
    p.Position = at; p.Size = size; p.Color = color; p.Visible = true
    return idx + 1
end

local function dline(pool, idx, from, to, color, thick)
    local p = pool[idx]
    if not p then p = Drawing.new("Line"); pool[idx] = p end
    p.From = from; p.To = to; p.Color = color; p.Thickness = thick; p.Visible = true
    return idx + 1
end

-- drawBox (ported from Salad Visuals source, adapted for S.BoxColor per-call)
local function drawBox(b, at, sz, corners, color)
    local x1, y1 = math.floor(at.X), math.floor(at.Y)
    local x2, y2 = math.floor(at.X + sz.X), math.floor(at.Y + sz.Y)
    local w, h   = x2 - x1, y2 - y1
    if w <= 0 or h <= 0 then
        hidePool(b.bars, 1); hidePool(b.outlines, 1); hidePool(b.edges, 1)
        b.fill.Visible = false; return
    end

    b.fill.Visible = S.BoxFilled
    if S.BoxFilled then
        b.fill.Position    = Vector2.new(x1, y1)
        b.fill.Size        = Vector2.new(w, h)
        b.fill.Color       = color
        b.fill.Transparency = S.BoxFillOpacity / 100
    end

    local thick = S.BoxThickness
    local style = S.BoxStyle
    local i, o, e = 1, 1, 1

    if style == "Corner" or style == "Bracket" then
        local tall = style == "Bracket"
        local lx   = math.max(1, math.floor(w * 0.28))
        local ly   = tall and h or math.max(1, math.floor(h * 0.28))

        o = rect(b.outlines, o, Vector2.new(x1-1,y1-1),          Vector2.new(lx+2,  thick+2), DARK)
        o = rect(b.outlines, o, Vector2.new(x2-lx-1,y1-1),       Vector2.new(lx+2,  thick+2), DARK)
        o = rect(b.outlines, o, Vector2.new(x1-1,y2-thick-1),     Vector2.new(lx+2,  thick+2), DARK)
        o = rect(b.outlines, o, Vector2.new(x2-lx-1,y2-thick-1), Vector2.new(lx+2,  thick+2), DARK)
        o = rect(b.outlines, o, Vector2.new(x1-1,y1-1),          Vector2.new(thick+2,ly+2),   DARK)
        o = rect(b.outlines, o, Vector2.new(x2-thick-1,y1-1),    Vector2.new(thick+2,ly+2),   DARK)

        i = rect(b.bars, i, Vector2.new(x1,y1),       Vector2.new(lx,thick),  color)
        i = rect(b.bars, i, Vector2.new(x2-lx,y1),    Vector2.new(lx,thick),  color)
        i = rect(b.bars, i, Vector2.new(x1,y2-thick), Vector2.new(lx,thick),  color)
        i = rect(b.bars, i, Vector2.new(x2-lx,y2-thick),Vector2.new(lx,thick),color)
        i = rect(b.bars, i, Vector2.new(x1,y1),       Vector2.new(thick,ly),  color)
        i = rect(b.bars, i, Vector2.new(x2-thick,y1), Vector2.new(thick,ly),  color)

        if not tall then
            o = rect(b.outlines, o, Vector2.new(x1-1,y2-ly-1),       Vector2.new(thick+2,ly+2), DARK)
            o = rect(b.outlines, o, Vector2.new(x2-thick-1,y2-ly-1), Vector2.new(thick+2,ly+2), DARK)
            i = rect(b.bars, i, Vector2.new(x1,y2-ly),       Vector2.new(thick,ly), color)
            i = rect(b.bars, i, Vector2.new(x2-thick,y2-ly), Vector2.new(thick,ly), color)
        end
    else -- Full
        o = rect(b.outlines, o, Vector2.new(x1-1,y1-1),          Vector2.new(w+2,   thick+2), DARK)
        o = rect(b.outlines, o, Vector2.new(x1-1,y2-thick-1),    Vector2.new(w+2,   thick+2), DARK)
        o = rect(b.outlines, o, Vector2.new(x1-1,y1-1),          Vector2.new(thick+2,h+2),    DARK)
        o = rect(b.outlines, o, Vector2.new(x2-thick-1,y1-1),    Vector2.new(thick+2,h+2),    DARK)

        i = rect(b.bars, i, Vector2.new(x1,y1),          Vector2.new(w,thick), color)
        i = rect(b.bars, i, Vector2.new(x1,y2-thick),    Vector2.new(w,thick), color)
        i = rect(b.bars, i, Vector2.new(x1,y1),          Vector2.new(thick,h), color)
        i = rect(b.bars, i, Vector2.new(x2-thick,y1),    Vector2.new(thick,h), color)
    end

    hidePool(b.bars, i); hidePool(b.outlines, o); hidePool(b.edges, e)
end

local function hideBox(b)
    b.fill.Visible     = false
    b.nameLabel.Visible = false
    b.distLabel.Visible = false
    hidePool(b.bars, 1); hidePool(b.outlines, 1); hidePool(b.edges, 1)
end

-- drawSkeleton (ported from Salad Visuals source)
local function drawSkeleton(b, char, camera)
    local boneList = char:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
    local viewport = camera.ViewportSize
    for idx, pair in ipairs(boneList) do
        local from = char:FindFirstChild(pair[1])
        local to   = char:FindFirstChild(pair[2])
        if not b.bones[idx] then
            local l = Drawing.new("Line"); l.Thickness = 1; l.Visible = false
            b.bones[idx] = l
        end
        local bone = b.bones[idx]
        if from and to and Visibility.Part(camera, from, char) and Visibility.Part(camera, to, char) then
            local a, c = clipNear(
                camera.CFrame:PointToObjectSpace(from.Position),
                camera.CFrame:PointToObjectSpace(to.Position)
            )
            if a then
                a = projectPoint(a, camera, viewport)
                c = projectPoint(c, camera, viewport)
                if math.abs(a.X) < 10000 and math.abs(a.Y) < 10000
                    and math.abs(c.X) < 10000 and math.abs(c.Y) < 10000 then
                    bone.From = Vector2.new(a.X, a.Y)
                    bone.To   = Vector2.new(c.X, c.Y)
                    bone.Color   = S.SkeletonColor
                    bone.Visible = true
                else
                    bone.Visible = false
                end
            else
                bone.Visible = false
            end
        else
            bone.Visible = false
        end
    end
    for i = #boneList + 1, #b.bones do b.bones[i].Visible = false end
end

-- ─── Highlight chams ────────────────────────────────────────────────────────

local function ensureHL(player, char)
    local hl    = highlights[player]
    local state = hlState[player]
    if not hl or not hl.Parent then
        hl = Instance.new("Highlight")
        hl.Name         = "MM2Visuals_HL_" .. player.Name
        hl.DepthMode    = Enum.HighlightDepthMode.Occluded
        hl.OutlineTransparency = 1
        hl.FillTransparency    = S.ChamsFillT
        hl.Parent = CoreGui
        highlights[player] = hl
        state = {}
        hlState[player] = state
    end
    if state.Char ~= char then state.Char = char; hl.Adornee = char end
    hl.Enabled            = true
    hl.FillColor          = S.ChamsFill
    hl.FillTransparency   = S.ChamsFillT
    hl.OutlineColor       = S.ChamsOutline
    hl.OutlineTransparency = S.ChamsOutlineT
end

local function disableHL(player)
    local hl = highlights[player]
    if hl then hl.Enabled = false end
end

-- ─── Material chams per-player ──────────────────────────────────────────────

local matLastChar = {}
local matClock    = {}

local function applyMatChams(player, char)
    local now = os.clock()
    if matClock[player] and now - matClock[player] < 0.15 then return end
    matClock[player] = now
    if matLastChar[player] ~= char then
        if matLastChar[player] then restoreModel(matLastChar[player]) end
        matLastChar[player] = char
    end
    paintModel(char, S.MatStyle, S.MatColor, S.MatTransp)
end

local function clearMatChams(player)
    if matLastChar[player] then
        restoreModel(matLastChar[player])
        matLastChar[player] = nil
        matClock[player]    = nil
    end
end

-- ─── Drop player ────────────────────────────────────────────────────────────

local function dropPlayer(player)
    local b = bundles[player]
    if b then
        pcall(function() b.nameLabel:Remove() end)
        pcall(function() b.distLabel:Remove() end)
        pcall(function() b.fill:Remove() end)
        for _, p in ipairs(b.bars)     do pcall(function() p:Remove() end) end
        for _, p in ipairs(b.outlines) do pcall(function() p:Remove() end) end
        for _, p in ipairs(b.edges)    do pcall(function() p:Remove() end) end
        for _, p in ipairs(b.bones)    do pcall(function() p:Remove() end) end
        bundles[player] = nil
    end
    local hl = highlights[player]
    if hl and hl.Parent then hl:Destroy() end
    highlights[player] = nil
    hlState[player]    = nil
    clearMatChams(player)
end

Players.PlayerRemoving:Connect(dropPlayer)

-- ─── Main render loop ───────────────────────────────────────────────────────

RunService.RenderStepped:Connect(function()
    if not S.Enabled then
        for pl in pairs(bundles) do
            local b = bundles[pl]
            if b then hideBox(b) end
            disableHL(pl)
        end
        return
    end

    local camera   = Render.camera()
    if not camera then return end
    local viewport = camera.ViewportSize
    local camPos   = camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then goto cont end

        local char  = player.Character
        local root  = char and char:FindFirstChild("HumanoidRootPart")
        local human = char and char:FindFirstChildWhichIsA("Humanoid")
        local alive = root and human and human.Health > 0

        local b = getBundle(player)

        if not alive then
            hideBox(b)
            for _, bone in ipairs(b.bones) do bone.Visible = false end
            disableHL(player)
            clearMatChams(player)
            goto cont
        end

        -- Highlight chams
        if S.Chams then
            ensureHL(player, char)
        else
            disableHL(player)
        end

        -- Material chams
        if S.MatChams then
            applyMatChams(player, char)
        else
            clearMatChams(player)
        end

        -- Box + name + distance
        local visible = Visibility.Character(camera, char, root)
        local at, sz, corners = projectBox(char, camera, viewport)

        if at and sz then
            if S.Box then
                drawBox(b, at, sz, corners, S.BoxColor)
            else
                hidePool(b.bars, 1); hidePool(b.outlines, 1); hidePool(b.edges, 1)
                b.fill.Visible = false
            end

            if S.Name then
                b.nameLabel.Text     = player.DisplayName
                b.nameLabel.Color    = S.NameColor
                b.nameLabel.Position = Vector2.new(at.X + sz.X * 0.5, at.Y - 15)
                b.nameLabel.Visible  = true
            else
                b.nameLabel.Visible = false
            end

            if S.Distance then
                local dist = math.round((root.Position - camPos).Magnitude)
                b.distLabel.Text     = dist .. "m"
                b.distLabel.Color    = S.DistColor
                b.distLabel.Position = Vector2.new(at.X + sz.X * 0.5, at.Y + sz.Y + 2)
                b.distLabel.Visible  = true
            else
                b.distLabel.Visible = false
            end
        else
            hideBox(b)
        end

        -- Skeleton
        if S.Skeleton and visible then
            drawSkeleton(b, char, camera)
        else
            for _, bone in ipairs(b.bones) do bone.Visible = false end
        end

        ::cont::
    end
end)

-- ─── Keybind toggle ─────────────────────────────────────────────────────────

UserInput.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == S.ToggleKey then
        S.Enabled = not S.Enabled
    end
end)

print("[MM2 Visuals] Loaded | " .. tostring(S.ToggleKey) .. " = toggle")
