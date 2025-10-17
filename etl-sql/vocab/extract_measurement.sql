SELECT 
    t.LABID,
	t.LABNM,
    v.ItemNumber,
    v.ItemName,
	v.Symbol
FROM 
	[$(SrcSchema)].[INFLABM] t
CROSS APPLY (
    VALUES
        -- item 1 to 40
        ('Item1', t.Item1, t.symbol1),
        ('Item2', t.Item2, t.symbol2),
        ('Item3', t.Item3, t.symbol3),
        ('Item4', t.Item4, t.symbol4),
        ('Item5', t.Item5, t.symbol5),
        ('Item6', t.Item6, t.symbol6),
        ('Item7', t.Item7, t.symbol7),
        ('Item8', t.Item8, t.symbol8),
        ('Item9', t.Item9, t.symbol9),
        ('Item10', t.Item10, t.symbol10),
        ('Item11', t.Item11, t.symbol11),
        ('Item12', t.Item12, t.symbol12),
        ('Item13', t.Item13, t.symbol13),
        ('Item14', t.Item14, t.symbol14),
        ('Item15', t.Item15, t.symbol15),
        ('Item16', t.Item16, t.symbol16),
        ('Item17', t.Item17, t.symbol17),
        ('Item18', t.Item18, t.symbol18),
        ('Item19', t.Item19, t.symbol19),
        ('Item20', t.Item20, t.symbol20),
        ('Item21', t.Item21, t.symbol21),
        ('Item22', t.Item22, t.symbol22),
        ('Item23', t.Item23, t.symbol23),
        ('Item24', t.Item24, t.symbol24),
        ('Item25', t.Item25, t.symbol25),
        ('Item26', t.Item26, t.symbol26),
        ('Item27', t.Item27, t.symbol27),
        ('Item28', t.Item28, t.symbol28),
        ('Item29', t.Item29, t.symbol29),
        ('Item30', t.Item30, t.symbol30),
        ('Item31', t.Item31, t.symbol31),
        ('Item32', t.Item32, t.symbol32),
        ('Item33', t.Item33, t.symbol33),
        ('Item34', t.Item34, t.symbol34),
        ('Item35', t.Item35, t.symbol35),
        ('Item36', t.Item36, t.symbol36),
        ('Item37', t.Item37, t.symbol37),
        ('Item38', t.Item38, t.symbol38),
        ('Item39', t.Item39, t.symbol39),
        ('Item40', t.Item40, t.symbol40),
) AS v(ItemNumber, ItemName, Symbol)
WHERE 
    v.ItemName IS NOT NULL;
    AND LEN(v.ItemName) > 0;

