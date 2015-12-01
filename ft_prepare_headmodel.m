function [headmodel, cfg] = ft_prepare_headmodel(cfg, data)

% FT_PREPARE_HEADMODEL constructs a volume conduction model from the geometry
% of the head. The volume conduction model specifies how currents that are
% generated by sources in the brain, e.g. dipoles, are propagated through the
% tissue and how these result in externally measureable EEG potentials or MEG
% fields.
%
% FieldTrip implements a variety of forward solutions, partially with internal
% code and some of them using external toolboxes or executables. Each of the
% forward solutions requires a set of configuration options which are listed
% below. This function takes care of all the preparatory steps in the
% construction of the volume conduction model and sets it up so that
% subsequent computations are efficient and fast.
%
% Use as
%   headmodel = ft_prepare_headmodel(cfg)       or
%   headmodel = ft_prepare_headmodel(cfg, mesh) with the output of FT_PREPARE_MESH or FT_READ_HEADSHAPE
%   headmodel = ft_prepare_headmodel(cfg, seg)  with the output of FT_VOLUMESEGMENT
%   headmodel = ft_prepare_headmodel(cfg, elec) with the output of FT_READ_SENS
%   headmodel = ft_prepare_headmodel(cfg, grid) with the output of FT_PREPARE_LEADFIELD
%
% In general the input to this function is a geometrical description of the
% shape of the head and a description of the electrical conductivity. The
% geometrical description can be a set of surface points obtained from
% fT_READ_HEADSHAPE, a surface mesh that was obtained from FT_PREPARE_MESH or
% a segmented anatomical MRI that was obtained from FT_VOLUMESEGMENT.
%
% The cfg argument is a structure that can contain:
%   cfg.method         string that specifies the forward solution, see below
%   cfg.conductivity   a number or a vector containing the conductivities of the compartments
%   cfg.tissue         a string or integer, to be used in combination with a 'seg' for the
%                      second intput. If 'brain', 'skull', and 'scalp' are fields
%                      present in 'seg', then cfg.tissue need not be specified, as
%                      these are defaults, depending on cfg.method. Otherwise,
%                      cfg.tissue should refer to which field(s) of seg should be used.
%
% For EEG the following methods are available:
%   singlesphere       analytical single sphere model
%   concentricspheres  analytical concentric sphere model with up to 4 spheres
%   openmeeg           boundary element method, based on the OpenMEEG software
%   bemcp              boundary element method, based on the implementation from Christophe Phillips
%   dipoli             boundary element method, based on the implementation from Thom Oostendorp
%   asa                boundary element method, based on the (commercial) ASA software
%   simbio             finite element method, based on the SimBio software
%   fns                finite difference method, based on the FNS software
%   infinite           electric dipole in an infinite homogenous medium
%   halfspace          infinite homogenous medium on one side, vacuum on the other
%   besa               finite element leadfield matrix from BESA
%   interpolate        interpolate the precomputed leadfield
%
% For MEG the following methods are available:
%   openmeeg           boundary element method, based on the OpenMEEG software
%   singlesphere       analytical single sphere model
%   localspheres       local spheres model for MEG, one sphere per channel
%   singleshell        realisically shaped single shell approximation, based on the implementation from Guido Nolte
%   infinite           magnetic dipole in an infinite vacuum
%
% Each specific method has its own specific configuration options which are listed below.
%
% BEMCP, DIPOLI, OPENMEEG
%   cfg.tissue            see above; in combination with 'seg' input
%   cfg.isolatedsource    (optional)
%
% CONCENTRICSPHERES
%   cfg.tissue            see above; in combination with 'seg' input
%   cfg.fitind            (optional)
%
% LOCALSPHERES
%   cfg.grad
%   cfg.tissue            see above; in combination with 'seg' input; default options are 'brain' or 'scalp'
%   cfg.feedback          (optional)
%   cfg.radius            (optional)
%   cfg.maxradius         (optional)
%   cfg.baseline          (optional)
%
% SIMBIO
%   cfg.conductivity
%
% SINGLESHELL
%   cfg.tissue            see above; in combination with 'seg' input; default options are 'brain' or 'scalp'
%
% SINGLESPHERE
%   cfg.tissue            see above; in combination with 'seg' input; default options are 'brain' or 'scalp'; must be only 1 value
%
% INTERPOLATE
%    cfg.outputfile       (required) string, filename prefix for the output files
%
% BESA
%   cfg.headmodel         (required) string, filename of precomputed FEM leadfield
%   cfg.elecfile          (required) string, filename of electrode configuration for the FEM leadfield
%   cfg.outputfile        (required) string, filename prefix for the output files
%
% FNS
%   cfg.tissue
%   cfg.tissueval
%   cfg.conductivity
%   cfg.elec
%   cfg.grad
%   cfg.transform
%   cfg.unit
%
% HALFSPACE
%   cfg.point
%   cfg.submethod         (optional)
%
% More details for each of the specific methods can be found in the corresponding
% low-level function which is called FT_HEADMODEL_XXX where XXX is the method
% of choise.
%
% See also FT_PREPARE_SOURCEMODEL, FT_PREPARE_LEADFIELD, FT_PREPARE_MESH,
% FT_HEADMODEL_BEMCP, FT_HEADMODEL_ASA, FT_HEADMODEL_DIPOLI,
% FT_HEADMODEL_SIMBIO, FT_HEADMODEL_FNS, FT_HEADMODEL_HALFSPACE,
% FT_HEADMODEL_INFINITE, FT_HEADMODEL_OPENMEEG, FT_HEADMODEL_SINGLESPHERE,
% FT_HEADMODEL_CONCENTRICSPHERES, FT_HEADMODEL_LOCALSPHERES,
% FT_HEADMODEL_SINGLESHELL, FT_HEADMODEL_INTERPOLATE

% Copyright (C) 2011, Cristiano Micheli
% Copyright (C) 2011-2012, Jan-Mathijs Schoffelen, Robert Oostenveld
% Copyright (C) 2013, Robert Oostenveld, Johanna Zumer
%
% This file is part of FieldTrip, see http://www.ru.nl/neuroimaging/fieldtrip
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id$

revision = '$Id$';

% do the general setup of the function
ft_defaults
ft_preamble init
ft_preamble trackconfig
ft_preamble provenance

% the abort variable is set to true or false in ft_preamble_init
if abort
  return
end

% check if the input cfg is valid for this function
cfg = ft_checkconfig(cfg, 'required', 'method');
cfg = ft_checkconfig(cfg, 'deprecated', 'geom');
cfg = ft_checkconfig(cfg, 'forbidden', 'unit'); % see http://bugzilla.fcdonders.nl/show_bug.cgi?id=2375
cfg = ft_checkconfig(cfg, 'renamed', {'geom', 'headshape'});
cfg = ft_checkconfig(cfg, 'renamedval', {'method', 'bem_openmeeg', 'openmeeg'});
cfg = ft_checkconfig(cfg, 'renamedval', {'method', 'bem_dipoli', 'dipoli'});
cfg = ft_checkconfig(cfg, 'renamedval', {'method', 'bem_cp', 'bemcp'});
cfg = ft_checkconfig(cfg, 'renamedval', {'method', 'nolte', 'singleshell'});
cfg = ft_checkconfig(cfg, 'renamed', {'hdmfile', 'headmodel'});
cfg = ft_checkconfig(cfg, 'renamed', {'vol',     'headmodel'});

% set the general defaults
cfg.headshape       = ft_getopt(cfg, 'headshape');
cfg.conductivity    = ft_getopt(cfg, 'conductivity');

% volume related options
cfg.tissue          = ft_getopt(cfg, 'tissue');
cfg.smooth          = ft_getopt(cfg, 'smooth');
cfg.threshold       = ft_getopt(cfg, 'threshold');

% other options
cfg.numvertices     = ft_getopt(cfg, 'numvertices', 3000);
cfg.isolatedsource  = ft_getopt(cfg, 'isolatedsource'); % used for dipoli and openmeeg
cfg.fitind          = ft_getopt(cfg, 'fitind');         % used for concentricspheres
cfg.point           = ft_getopt(cfg, 'point');          % used for halfspace
cfg.submethod       = ft_getopt(cfg, 'submethod');      % used for halfspace
cfg.feedback        = ft_getopt(cfg, 'feedback');
cfg.radius          = ft_getopt(cfg, 'radius');
cfg.maxradius       = ft_getopt(cfg, 'maxradius');
cfg.baseline        = ft_getopt(cfg, 'baseline');
cfg.singlesphere    = ft_getopt(cfg, 'singlesphere');
cfg.tissueval       = ft_getopt(cfg, 'tissueval');      % used for simbio
cfg.transform       = ft_getopt(cfg, 'transform');
cfg.siunits         = ft_getopt(cfg, 'siunits', 'no');  % yes/no, convert the input and continue with SI units
cfg.smooth          = ft_getopt(cfg, 'smooth');         % used for interpolate
cfg.headmodel       = ft_getopt(cfg, 'headmodel');      % can contain CTF localspheres model

if nargin>1,
  % the data should describe the geometrical mesh
  if isfield(data, 'bnd')
    data = data.bnd;
  end
  % check if the input data is valid for this function and ensure that it has the units specified
  data = ft_checkdata(data, 'hasunit', 'yes');
  % replace pnt by pos
  data = fixpos(data);
else
  data = [];
end

if istrue(cfg.siunits)
  % convert to SI units
  if ~isempty(data)
    data = ft_convert_units(data, 'm');
  end
  if isfield(cfg, 'grad') && ~isempty(cfg.grad)
    cfg.grad = ft_convert_units(cfg.grad, 'm');
  end
  if isfield(cfg, 'elec') && ~isempty(cfg.elec)
    cfg.elec = ft_convert_units(cfg.elec, 'm');
  end
end

% if the conductivity is in the data cfg.conductivity is overwritten
if nargin>1 && isfield(data, 'cond')
  cfg.conductivity = data.cond;
end

% boolean variables to manages the different geometrical input data objects
input_mesh  = ft_datatype(data, 'mesh');
input_seg   = ft_datatype(data, 'segmentation');
input_elec  = ft_datatype(data, 'sens');
input_pos   = ~input_mesh && isfield(data, 'pos'); % surface points without triangulation

% the construction of the volume conductor model is performed below
switch cfg.method
  
  case 'interpolate'
    % the "data" here represents the output of FT_PREPARE_LEADFIELD, i.e. a regular dipole
    % grid with pre-computed leadfields
    sens = ft_fetch_sens(cfg, data);
    headmodel = ft_headmodel_interpolate(cfg.outputfile, sens, data, 'smooth', cfg.smooth);
    
  case 'besa'
    % the cfg.headmodel? points to the filename of the FEM solution that was computed
    % in BESA, cfg.elecfile should point to the corresponding electrode specification
    sens = ft_fetch_sens(cfg, data);
    headmodel = ft_headmodel_interpolate(cfg.outputfile, sens, cfg.headmodel, 'smooth', cfg.smooth);
    
  case 'asa'
    if ~ft_filetype(cfg.headmodel, 'asa_vol')
      error('You must supply a valid cfg.headmodel for use with ASA headmodel')
    end
    headmodel = ft_headmodel_asa(cfg.headmodel);
    
  case {'bemcp' 'dipoli' 'openmeeg'}
    % the low-level functions all need a mesh
    if input_mesh
      if ~isfield(data, 'tri')
        error('Please give a mesh with closed triangulation');
      else
        geometry = data;
      end
    elseif input_seg
      tmpcfg = [];
      tmpcfg.numvertices = cfg.numvertices;
      tmpcfg.tissue = cfg.tissue;
      geometry = ft_prepare_mesh(tmpcfg, data);
    else
      error('Either a segmentated MRI or data with closed triangulated mesh is required as data input for the bemcp, dipoli or openmeeg method');
    end
    
    if strcmp(cfg.method, 'bemcp')
      headmodel = ft_headmodel_bemcp(geometry, 'conductivity', cfg.conductivity);
      if any(isnan(headmodel.mat(:)))
        % HACK add a little bit of noise, with the NatMEG tutorial data, I discovered that this prevents the warning
        % Matrix is singular, close to singular or badly scaled. Results may be inaccurate. RCOND = NaN.
        geometry(1).pos = geometry(1).pos + randn(size(geometry(1).pos))*scalingfactor('um', geometry(1).unit);
        geometry(2).pos = geometry(2).pos + randn(size(geometry(2).pos))*scalingfactor('um', geometry(2).unit);
        geometry(3).pos = geometry(3).pos + randn(size(geometry(3).pos))*scalingfactor('um', geometry(3).unit);
        warning('NaN detected, trying once more with slightly different vertex positions');
        headmodel = ft_headmodel_bemcp(geometry, 'conductivity', cfg.conductivity);
      end
    elseif strcmp(cfg.method, 'dipoli')
      headmodel = ft_headmodel_dipoli(geometry, 'conductivity', cfg.conductivity, 'isolatedsource', cfg.isolatedsource);
    else
      headmodel = ft_headmodel_openmeeg(geometry, 'conductivity', cfg.conductivity, 'isolatedsource', cfg.isolatedsource);
    end
    
  case 'concentricspheres'
    % the low-level functions needs surface points, triangles are not needed
    if input_mesh || input_pos
      geometry = data;
    elseif input_seg
      tmpcfg = [];
      tmpcfg.numvertices = cfg.numvertices;
      tmpcfg.tissue = cfg.tissue;
      geometry = ft_prepare_mesh(tmpcfg, data);
    elseif input_elec
      geometry.pos = data.chanpos;
      geometry.unit = data.unit;
    elseif ~isempty(cfg.headshape) && isnumeric(cfg.headshape)
      geometry.pos = cfg.headshape;
    elseif ~isempty(cfg.headshape) && isstruct(cfg.headshape)
      geometry = cfg.headshape;
    elseif ~isempty(cfg.headshape) && ischar(cfg.headshape)
      geometry = ft_read_headshape(cfg.headshape);
    else
      error('You must give a mesh, segmented MRI, sensor data type, or cfg.headshape');
    end
    
    headmodel = ft_headmodel_concentricspheres(geometry, 'conductivity', cfg.conductivity, 'fitind', cfg.fitind);
    
  case 'halfspace'
    if input_mesh || input_pos
      geometry = data;
    else
      error('a surface mesh is required as input for the halfspace method');
    end
    if isempty(cfg.point)
      error('cfg.point is required for halfspace method');
    end
    
    headmodel = ft_headmodel_halfspace(geometry, cfg.point, 'conductivity', cfg.conductivity, 'sourcemodel', cfg.submethod);
    
  case 'infinite'
    % this takes no input arguments
    headmodel = ft_headmodel_infinite();
    
  case {'localspheres' 'singlesphere' 'singleshell'}
    cfg.grad = ft_getopt(cfg, 'grad');           % used for localspheres
    
    % these three methods all require a set of surface points
    if input_mesh || input_pos
      geometry = data;
    elseif input_seg
      tmpcfg = [];
      tmpcfg.numvertices = cfg.numvertices;
      if ~isempty(cfg.tissue)
        % extract the specified surface
        tmpcfg.tissue = cfg.tissue;
        geometry = ft_prepare_mesh(tmpcfg, data);
      else
        % try to extract either the brain or scalp surface
        geometry = [];
        if isempty(geometry)
          try
            tmpcfg.tissue = 'brain';
            geometry = ft_prepare_mesh(tmpcfg, data);
          end
        end
        if isempty(geometry)
          try
            tmpcfg.tissue = 'scalp';
            geometry = ft_prepare_mesh(tmpcfg, data);
          end
        end
        if isempty(geometry)
          error('please specificy cfg.tissue and pass an appropriate segmented MRI as input data')
        end
      end
    elseif input_elec
      geometry.pos = data.chanpos;
      geometry.unit = data.unit;
    elseif ~isempty(cfg.headshape) && isnumeric(cfg.headshape)
      geometry.pos = cfg.headshape;
    elseif ~isempty(cfg.headshape) && isstruct(cfg.headshape)
      geometry = cfg.headshape;
    elseif ~isempty(cfg.headshape) && ischar(cfg.headshape)
      geometry = ft_read_headshape(cfg.headshape);
    elseif ~isempty(cfg.headmodel)
      % the CTF *.hdm file will be read further down
    else
      error('this requires a mesh, set of surface points or a segmented mri');
    end
    
    switch cfg.method
      case 'singlesphere'
        if ~isempty(cfg.headmodel)
          % read the volume conduction model from a CTF *.hdm file
          tmp = ft_read_vol(cfg.headmodel);
          try
            % the single sphere is contained in the "orig" field
            headmodel = [];
            headmodel.r =  tmp.orig.MEG_Sphere.RADIUS;
            headmodel.o = [tmp.orig.MEG_Sphere.ORIGIN_X tmp.orig.MEG_Sphere.ORIGIN_Y tmp.orig.MEG_Sphere.ORIGIN_Z];
            headmodel.unit = 'cm';
          catch
            error('the volume conduction model in "%s" is invalid', cfg.headmodel);
          end
        else
          % construct the volume conduction model
          headmodel = ft_headmodel_singlesphere(geometry, 'conductivity', cfg.conductivity);
        end % headmodel
      case 'localspheres'
        if ~isempty(cfg.headmodel)
          % read the volume conduction model from a CTF *.hdm file
          tmp = ft_read_vol(cfg.headmodel);
          try
            headmodel = [];
            headmodel.label = tmp.label;
            headmodel.r = tmp.r;
            headmodel.o = tmp.o;
            headmodel.unit = 'cm';
          catch
            error('the volume conduction model in "%s" is invalid', cfg.headmodel);
          end
        else
          % construct the volume conduction model
          cfg.grad = ft_getopt(cfg, 'grad');
          if isempty(cfg.grad)
            error('for cfg.method = %s, you need to supply a cfg.grad structure', cfg.method);
          end
          headmodel = ft_headmodel_localspheres(geometry, cfg.grad, 'feedback', cfg.feedback, 'radius', cfg.radius, 'maxradius', cfg.maxradius, 'baseline', cfg.baseline, 'singlesphere', cfg.singlesphere);
        end % headmodel
      case 'singleshell'
        if ~isfield(geometry, 'tri')
          tmpcfg = [];
          tmpcfg.headshape = geometry;
          geometry = ft_prepare_mesh(tmpcfg);
        end
        headmodel = ft_headmodel_singleshell(geometry);
    end
    
  case {'simbio'}
    if input_elec || isfield(data, 'pos') || input_mesh
      geometry = data; % more serious checks of validity of the mesh occur inside ft_headmodel_simbio
    else
      error('You must provide a mesh with tetrahedral or hexahedral elements, where each element has a scalar or tensor conductivity');
    end
    headmodel = ft_headmodel_simbio(geometry, 'conductivity', cfg.conductivity);
    
  case {'fns'}
    if input_seg
      data = ft_datatype_segmentation(data, 'segmentationstyle', 'indexed');
    else
      error('segmented MRI must be given as data input')
    end
    sens = ft_fetch_sens(cfg, data);
    headmodel = ft_headmodel_fns(data.seg, 'tissue', cfg.tissue, 'tissueval', cfg.tissueval, 'tissuecond', cfg.conductivity, 'sens', sens, 'transform', cfg.transform);
    
  otherwise
    error('unsupported method "%s"', cfg.method);
end % switch method

% ensure that the geometrical units are specified
if ~ft_voltype(headmodel, 'infinite'),
  headmodel = ft_convert_units(headmodel);
end

% do the general cleanup and bookkeeping at the end of the function
ft_postamble trackconfig
ft_postamble provenance
ft_postamble previous data
ft_postamble history headmodel
